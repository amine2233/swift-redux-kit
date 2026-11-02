import Observation
import ReduxKit

/// A store wrapper that adds undo/redo functionality to a Redux store.
///
/// The ``UndoableStore`` wraps an existing ``Store`` and maintains a history of state changes,
/// allowing navigation through previous states via undo/redo operations.
/// It provides configurable history limits and the ability to group actions together.
@Observable @dynamicMemberLookup @MainActor
public final class UndoableStore<
    State: Sendable & Hashable,
    Action: Sendable & Actionable
>: UndoableStoreable {
    /// The underlying store managing the current state
    private let store: Store<State, Action>

    /// History of previous states (stack for undo)
    private var past: [State] = []

    /// History of future states (stack for redo)
    private var future: [State] = []

    /// Maximum number of states to keep in history (0 = unlimited)
    private let historyLimit: Int

    /// Whether the next action should be grouped with the previous one (no new history entry)
    private var isGrouping: Bool = false

    /// Creates an undoable store wrapping the provided store.
    ///
    /// - Parameters:
    ///   - store: The underlying store to wrap
    ///   - historyLimit: Maximum number of states in history (default: 0 = unlimited)
    public init(store: Store<State, Action>, historyLimit: Int = 0) {
        self.store = store
        self.historyLimit = max(0, historyLimit)
    }

    /// Convenience initializer to create both the store and undoable wrapper.
    ///
    /// - Parameters:
    ///   - initialState: The initial state
    ///   - reducer: The reducer for state mutations
    ///   - middlewares: The middlewares for side effects
    ///   - services: The services emitting actions from outside the store, started by ``run()``
    ///   - historyLimit: Maximum number of states in history (default: 0 = unlimited)
    public convenience init(
        initialState: State,
        reducer: some Reducer<State, Action>,
        middlewares: some Collection<any Middleware<State, Action>>,
        services: [any StoreService<Action>] = [],
        historyLimit: Int = 0
    ) {
        let store = Store(
            initialState: initialState,
            reducer: reducer,
            middlewares: middlewares,
            services: services
        )
        self.init(store: store, historyLimit: historyLimit)
    }

    /// Convenience initializer to create both the store and undoable wrapper without middlewares.
    ///
    /// - Parameters:
    ///   - initialState: The initial state
    ///   - reducer: The reducer for state mutations
    ///   - services: The services emitting actions from outside the store, started by ``run()``
    ///   - historyLimit: Maximum number of states in history (default: 0 = unlimited)
    public convenience init(
        initialState: State,
        reducer: some Reducer<State, Action>,
        services: [any StoreService<Action>] = [],
        historyLimit: Int = 0
    ) {
        let store = Store(
            initialState: initialState,
            reducer: reducer,
            middlewares: [any Middleware<State, Action>](),
            services: services
        )
        self.init(store: store, historyLimit: historyLimit)
    }

    /// A subscript providing access to the current state of the store.
    public subscript<T>(dynamicMember keyPath: KeyPath<State, T> & Sendable) -> T {
        store[dynamicMember: keyPath]
    }

    /// Runs every service registered on the underlying store.
    ///
    /// Actions emitted by the services go through this store's ``send(_:)``, so they are recorded in
    /// the undo history.
    public func run() async {
        await runServices(store.services) { [self] action in
            await send(action)
        }
    }

    /// Sends an action to the store and records the state change in history.
    ///
    /// - Parameter action: The action to send
    public func send(_ action: Action) async {
        let oldState = currentState
        await store.send(action)
        let newState = currentState

        // Only record if state actually changed
        guard newState != oldState else { return }

        if isGrouping {
            // When grouping, don't add to history (group with previous action)
            isGrouping = false
        } else {
            // Add current state to history
            past.append(oldState)

            // Clear future (can't redo after new action)
            future.removeAll()

            // Apply history limit
            if historyLimit > 0, past.count > historyLimit {
                past.removeFirst(past.count - historyLimit)
            }
        }
    }

    /// Undoes the last action by restoring the previous state.
    ///
    /// - Returns: `true` if undo was performed, `false` if nothing to undo
    @discardableResult
    public func undo() async -> Bool {
        guard canUndo else { return false }

        let currentState = self.currentState
        let previousState = past.removeLast()

        // Move current state to future
        future.append(currentState)

        // Restore previous state directly (bypass reducer)
        restoreState(previousState)

        return true
    }

    /// Redoes the last undone action by restoring the next state.
    ///
    /// - Returns: `true` if redo was performed, `false` if nothing to redo
    @discardableResult
    public func redo() async -> Bool {
        guard canRedo else { return false }

        let currentState = self.currentState
        let nextState = future.removeLast()

        // Move current state to past
        past.append(currentState)

        // Restore next state directly (bypass reducer)
        restoreState(nextState)

        return true
    }

    /// Groups the next action with the current state (won't create new history entry).
    ///
    /// Useful for operations that should be treated as a single undoable action.
    public func beginGrouping() {
        isGrouping = true
    }

    /// Clears all undo/redo history.
    public func clearHistory() {
        past.removeAll()
        future.removeAll()
    }

    /// Whether undo is available.
    public var canUndo: Bool {
        !past.isEmpty
    }

    /// Whether redo is available.
    public var canRedo: Bool {
        !future.isEmpty
    }

    /// The number of states in the undo history.
    public var undoCount: Int {
        past.count
    }

    /// The number of states in the redo history.
    public var redoCount: Int {
        future.count
    }

    /// Direct access to the underlying store (use with caution).
    public var underlyingStore: Store<State, Action> {
        store
    }

    /// Gets the current state from the underlying store.
    private var currentState: State {
        // Access state through a dummy keyPath since Store doesn't expose state directly
        store[dynamicMember: \State.self]
    }

    /// Restores state directly using the Store's setState method.
    /// This bypasses the reducer and middleware to restore a previous state snapshot.
    private func restoreState(_ state: State) {
        store.setState(state)
    }
}

// MARK: - Derived Store

extension UndoableStore {
    /// Use this method to create another ``UndoableStore`` deriving from the current one.
    @available(*, deprecated, message: "Use multiple stores instead of derived store")
    public func derived<DerivedState: Hashable, DerivedAction: Hashable>(
        deriveState: @Sendable @escaping (State) -> DerivedState,
        deriveAction: @Sendable @escaping (DerivedAction) -> Action
    ) -> UndoableStore<DerivedState, DerivedAction> {
        let derivedStore = UndoableStore<DerivedState, DerivedAction>(
            initialState: deriveState(currentState),
            reducer: IdentityReducer(),
            middlewares: [
                ClosureMiddleware { [weak self] _, action in
                    guard let self else { return nil }

                    await self.send(deriveAction(action))
                    return nil
                }
            ],
            historyLimit: historyLimit
        )

        enableStateObservation(for: derivedStore, deriveState: deriveState)

        return derivedStore
    }

    private func enableStateObservation<DerivedState: Hashable, DerivedAction: Hashable>(
        for derivedStore: UndoableStore<DerivedState, DerivedAction>,
        deriveState: @Sendable @escaping (State) -> DerivedState
    ) {
        withObservationTracking {
            let newState = deriveState(currentState)
            if derivedStore.currentState != newState {
                derivedStore.restoreState(newState)
            }
        } onChange: {
            Task {
                await self.enableStateObservation(for: derivedStore, deriveState: deriveState)
            }
        }
    }
}

// MARK: - SwiftUI Support

#if canImport(SwiftUI)
import SwiftUI

extension UndoableStore {
    /// Creates a `Binding` that allows two-way data binding with undo/redo support.
    ///
    /// - Parameters:
    ///   - extract: A closure to extract a value from the state
    ///   - embed: A closure to create an action from the new value
    ///
    /// - Returns: A `Binding` that records changes in undo history
    public func binding<Value: Equatable>(
        extract: @escaping (State) -> Value,
        embed: @escaping (Value) -> Action
    ) -> Binding<Value> {
        .init(
            get: { extract(self.currentState) },
            set: { newValue in
                Task {
                    await self.send(embed(newValue))
                }
            }
        )
    }

    /// Creates a `Binding` using a keyPath with undo/redo support.
    ///
    /// - Parameters:
    ///   - keyPath: A key path to access a specific value from the state
    ///   - send: A closure that creates an action from the new value
    ///
    /// - Returns: A `Binding` that records changes in undo history
    public func binding<Value: Equatable>(
        _ keyPath: KeyPath<State, Value>,
        send: @escaping (Value) -> Action
    ) -> Binding<Value> {
        .init(
            get: { self.currentState[keyPath: keyPath] },
            set: { newValue in
                Task {
                    await self.send(send(newValue))
                }
            }
        )
    }
}
#endif
