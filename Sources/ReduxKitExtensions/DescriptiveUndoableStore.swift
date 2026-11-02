import Observation
import ReduxKit

// swiftlint:disable file_length
// Cohesive unit: the history types, the store, and its derived/SwiftUI extensions, which access the
// store's `private` members and so cannot move to a separate file.

/// Protocol for actions that can provide human-readable descriptions for undo/redo.
public protocol DescriptiveActionable: Actionable {
    /// A human-readable description of what this action does.
    /// Used in undo/redo UI (e.g., "Undo Add Item", "Redo Delete User")
    var undoDescription: String { get }
}

/// Represents a state change with the action that caused it.
public struct HistoryEntry<State: Sendable & Hashable, Action: Sendable & DescriptiveActionable> {
    /// The state before the action was applied
    public let state: State

    /// The action that was applied to reach the next state
    public let action: Action

    /// A human-readable description of what can be undone
    public var undoDescription: String {
        action.undoDescription
    }

    /// Creates a new history entry.
    ///
    /// - Parameters:
    ///   - state: The state before the action was applied
    ///   - action: The action that was applied
    public init(state: State, action: Action) {
        self.state = state
        self.action = action
    }
}

/// A store wrapper that adds undo/redo functionality with action descriptions.
///
/// The ``DescriptiveUndoableStore`` wraps an existing ``Store`` and maintains a history of both
/// states and the actions that caused them, allowing navigation through previous states via
/// undo/redo operations with descriptive labels for UI presentation.
@Observable @dynamicMemberLookup @MainActor
public final class DescriptiveUndoableStore<
    State: Sendable & Hashable,
    Action: Sendable & DescriptiveActionable
>: UndoableStoreable {
    /// The underlying store managing the current state
    private let store: Store<State, Action>

    /// History of previous state changes (stack for undo)
    private var past: [HistoryEntry<State, Action>] = []

    /// History of future state changes (stack for redo)
    private var future: [HistoryEntry<State, Action>] = []

    /// Maximum number of entries to keep in history (0 = unlimited)
    private let historyLimit: Int

    /// Whether the next action should be grouped with the previous one (no new history entry)
    private var isGrouping: Bool = false

    /// Creates a descriptive undoable store wrapping the provided store.
    ///
    /// - Parameters:
    ///   - store: The underlying store to wrap
    ///   - historyLimit: Maximum number of entries in history (default: 0 = unlimited)
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
    ///   - historyLimit: Maximum number of entries in history (default: 0 = unlimited)
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
    ///   - historyLimit: Maximum number of entries in history (default: 0 = unlimited)
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

    /// Sends an action to the store and records the state change with description in history.
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
            // Add state and action to history
            let entry = HistoryEntry(state: oldState, action: action)
            past.append(entry)

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
        let entry = past.removeLast()

        // Create entry for future (to enable redo)
        let futureEntry = HistoryEntry(state: currentState, action: entry.action)
        future.append(futureEntry)

        // Restore previous state directly (bypass reducer)
        restoreState(entry.state)

        return true
    }

    /// Redoes the last undone action by restoring the next state.
    ///
    /// - Returns: `true` if redo was performed, `false` if nothing to redo
    @discardableResult
    public func redo() async -> Bool {
        guard canRedo else { return false }

        let currentState = self.currentState
        let entry = future.removeLast()

        // Create entry for past (to enable undo)
        let pastEntry = HistoryEntry(state: currentState, action: entry.action)
        past.append(pastEntry)

        // Restore next state directly (bypass reducer)
        restoreState(entry.state)

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

    /// The number of entries in the undo history.
    public var undoCount: Int {
        past.count
    }

    /// The number of entries in the redo history.
    public var redoCount: Int {
        future.count
    }

    /// Gets the description of what the next undo operation will do.
    /// Returns `nil` if there's nothing to undo.
    public var nextUndoDescription: String? {
        past.last?.undoDescription
    }

    /// Gets the description of what the next redo operation will do.
    /// Returns `nil` if there's nothing to redo.
    public var nextRedoDescription: String? {
        future.last?.undoDescription
    }

    /// Gets all undo descriptions in the history (most recent first).
    public var undoDescriptions: [String] {
        past.reversed().map(\.undoDescription)
    }

    /// Gets all redo descriptions in the history (most recent first).
    public var redoDescriptions: [String] {
        future.map(\.undoDescription)
    }

    /// Gets the complete undo history with states and actions.
    public var undoHistory: [HistoryEntry<State, Action>] {
        Array(past)
    }

    /// Gets the complete redo history with states and actions.
    public var redoHistory: [HistoryEntry<State, Action>] {
        Array(future)
    }

    /// Undoes multiple steps at once.
    ///
    /// - Parameter count: Number of steps to undo
    /// - Returns: Number of steps actually undone
    @discardableResult
    public func undo(steps count: Int) async -> Int {
        var undoneCount = 0
        for _ in 0 ..< count {
            if await undo() {
                undoneCount += 1
            } else {
                break
            }
        }
        return undoneCount
    }

    /// Redoes multiple steps at once.
    ///
    /// - Parameter count: Number of steps to redo
    /// - Returns: Number of steps actually redone
    @discardableResult
    public func redo(steps count: Int) async -> Int {
        var redoneCount = 0
        for _ in 0 ..< count {
            if await redo() {
                redoneCount += 1
            } else {
                break
            }
        }
        return redoneCount
    }

    /// Undoes to a specific state in history by index (0 = oldest, undoCount-1 = most recent).
    ///
    /// - Parameter index: The history index to undo to
    /// - Returns: `true` if successful, `false` if index is invalid
    @discardableResult
    public func undoToIndex(_ index: Int) async -> Bool {
        guard index >= 0, index < past.count else { return false }

        let stepsToUndo = past.count - index
        await undo(steps: stepsToUndo)
        return true
    }

    /// Direct access to the underlying store (use with caution).
    public var underlyingStore: Store<State, Action> {
        store
    }

    /// Gets the current state from the underlying store.
    private var currentState: State {
        store[dynamicMember: \State.self]
    }

    /// Restores state directly using the Store's setState method.
    /// This bypasses the reducer and middleware to restore a previous state snapshot.
    private func restoreState(_ state: State) {
        store.setState(state)
    }
}

// MARK: - Derived Store

extension DescriptiveUndoableStore {
    /// Use this method to create another ``DescriptiveUndoableStore`` deriving from the current one.
    @available(*, deprecated, message: "Use multiple stores instead of derived store")
    public func derived<DerivedState: Hashable, DerivedAction: DescriptiveActionable>(
        deriveState: @Sendable @escaping (State) -> DerivedState,
        deriveAction: @Sendable @escaping (DerivedAction) -> Action
    ) -> DescriptiveUndoableStore<DerivedState, DerivedAction> {
        let derivedStore = DescriptiveUndoableStore<DerivedState, DerivedAction>(
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

    private func enableStateObservation<DerivedState: Hashable, DerivedAction: DescriptiveActionable>(
        for derivedStore: DescriptiveUndoableStore<DerivedState, DerivedAction>,
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

extension DescriptiveUndoableStore {
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
