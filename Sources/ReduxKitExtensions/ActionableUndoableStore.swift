import Observation
import ReduxKit

// swiftlint:disable file_length
// Cohesive unit: the undoable-action types, the store, and its derived/SwiftUI extensions, which
// access the store's `private` members and so cannot move to a separate file.

/// Protocol for states that can be accessed when creating inverse actions.
///
/// States conforming to this protocol can be queried by actions to determine
/// their inverse operation. This provides type-safe access to the state
/// when computing inverse actions.
public protocol UndoableState: Sendable & Hashable {}

/// Protocol for actions that can be undone by dispatching an inverse action.
///
/// Actions conforming to this protocol must provide their inverse action,
/// which when dispatched will reverse the original action's effects.
public protocol InvertibleActionable: Actionable {
    associatedtype State: UndoableState

    /// Returns the inverse action that reverses this action's effects.
    /// Return `nil` if the action cannot be undone.
    ///
    /// - Parameter state: The current state to help determine the inverse action
    /// - Returns: The inverse action, or `nil` if this action cannot be undone
    func inverse(state: State) -> Self?

    /// A human-readable description of what this action does.
    /// Used for undo/redo UI (e.g., "Undo Add Item", "Redo Delete User")
    var undoDescription: String { get }
}

/// Represents a recorded action in the undo/redo history.
public struct UndoableAction<Action: Sendable & InvertibleActionable>: Sendable {
    /// The original action that was performed
    public let action: Action

    /// The inverse action that can undo this action
    public let inverseAction: Action

    /// A human-readable description of what can be undone
    public var undoDescription: String {
        action.undoDescription
    }

    public init(action: Action, inverseAction: Action) {
        self.action = action
        self.inverseAction = inverseAction
    }
}

/// Enum representing undo/redo lifecycle actions that middleware can intercept.
///
/// These special actions are dispatched through the normal Store flow,
/// allowing middleware to respond to undo/redo operations.
public enum UndoRedoLifecycleAction<Action: Sendable & InvertibleActionable>: Actionable {
    /// Dispatched when undo is about to be performed
    case willUndo(action: Action)

    /// Dispatched when undo has been performed
    case didUndo(action: Action)

    /// Dispatched when redo is about to be performed
    case willRedo(action: Action)

    /// Dispatched when redo has been performed
    case didRedo(action: Action)
}

/// A store wrapper that adds undo/redo functionality by dispatching inverse actions through middleware.
///
/// Unlike ``UndoableStore`` which bypasses middleware when restoring state, ``ActionableUndoableStore``
/// dispatches the inverse actions through the normal Store flow. This allows middleware to intercept
/// undo/redo operations and perform side effects like API calls to reverse changes.
///
/// ## Example Use Case: API Request Reversal
///
/// ```swift
/// struct TaskState: UndoableState {
///     var tasks: [Task] = []
/// }
///
/// enum TaskAction: InvertibleActionable {
///     case createTask(id: String, title: String)
///     case deleteTask(id: String, title: String)
///
///     func inverse(state: TaskState) -> Self? {
///         switch self {
///         case let .createTask(id, title):
///             return .deleteTask(id: id, title: title)
///         case let .deleteTask(id, title):
///             return .createTask(id: id, title: title)
///         }
///     }
///
///     var undoDescription: String {
///         switch self {
///         case .createTask: return "Create Task"
///         case .deleteTask: return "Delete Task"
///         }
///     }
/// }
///
/// struct TaskMiddleware: Middleware {
///     func process(state: TaskState, with action: TaskAction) async -> TaskAction? {
///         switch action {
///         case let .createTask(id, title):
///             await api.createTask(id: id, title: title)
///         case let .deleteTask(id, _):
///             await api.deleteTask(id: id)
///         }
///         return nil
///     }
/// }
/// ```
@Observable @dynamicMemberLookup @MainActor
public final class ActionableUndoableStore<
    State: UndoableState,
    Action: Sendable & InvertibleActionable
>: UndoableStoreable where Action.State == State {
    /// The underlying store managing the current state
    private let store: Store<State, Action>

    /// History of previous actions (stack for undo)
    private var past: [UndoableAction<Action>] = []

    /// History of future actions (stack for redo)
    private var future: [UndoableAction<Action>] = []

    /// Maximum number of actions to keep in history (0 = unlimited)
    private let historyLimit: Int

    /// Whether the next action should be grouped with the previous one (no new history entry)
    private var isGrouping: Bool = false

    /// Whether we're currently performing an undo/redo operation (prevents recording these actions)
    private var isPerformingUndoRedo: Bool = false

    /// Optional lifecycle middleware that receives undo/redo lifecycle events
    private var lifecycleMiddlewares: [any Middleware<State, UndoRedoLifecycleAction<Action>>] = []

    /// Creates an actionable undoable store wrapping the provided store.
    ///
    /// - Parameters:
    ///   - store: The underlying store to wrap
    ///   - historyLimit: Maximum number of actions in history (default: 0 = unlimited)
    ///   - lifecycleMiddlewares: Optional middlewares that receive undo/redo lifecycle events
    public init(
        store: Store<State, Action>,
        historyLimit: Int = 0,
        lifecycleMiddlewares: [any Middleware<State, UndoRedoLifecycleAction<Action>>] = []
    ) {
        self.store = store
        self.historyLimit = max(0, historyLimit)
        self.lifecycleMiddlewares = lifecycleMiddlewares
    }

    /// Convenience initializer to create both the store and undoable wrapper.
    ///
    /// - Parameters:
    ///   - initialState: The initial state
    ///   - reducer: The reducer for state mutations
    ///   - middlewares: The middlewares for side effects
    ///   - services: The services emitting actions from outside the store, started by ``run()``
    ///   - historyLimit: Maximum number of actions in history (default: 0 = unlimited)
    ///   - lifecycleMiddlewares: Optional middlewares that receive undo/redo lifecycle events
    public convenience init(
        initialState: State,
        reducer: some Reducer<State, Action>,
        middlewares: some Collection<any Middleware<State, Action>>,
        services: [any StoreService<Action>] = [],
        historyLimit: Int = 0,
        lifecycleMiddlewares: [any Middleware<State, UndoRedoLifecycleAction<Action>>] = []
    ) {
        let store = Store(
            initialState: initialState,
            reducer: reducer,
            middlewares: middlewares,
            services: services
        )
        self.init(store: store, historyLimit: historyLimit, lifecycleMiddlewares: lifecycleMiddlewares)
    }

    /// Convenience initializer to create both the store and undoable wrapper without middlewares.
    ///
    /// - Parameters:
    ///   - initialState: The initial state
    ///   - reducer: The reducer for state mutations
    ///   - services: The services emitting actions from outside the store, started by ``run()``
    ///   - historyLimit: Maximum number of actions in history (default: 0 = unlimited)
    ///   - lifecycleMiddlewares: Optional middlewares that receive undo/redo lifecycle events
    public convenience init(
        initialState: State,
        reducer: some Reducer<State, Action>,
        services: [any StoreService<Action>] = [],
        historyLimit: Int = 0,
        lifecycleMiddlewares: [any Middleware<State, UndoRedoLifecycleAction<Action>>] = []
    ) {
        let store = Store(
            initialState: initialState,
            reducer: reducer,
            middlewares: [any Middleware<State, Action>](),
            services: services
        )
        self.init(store: store, historyLimit: historyLimit, lifecycleMiddlewares: lifecycleMiddlewares)
    }

    /// A subscript providing access to the current state of the store.
    public subscript<T>(dynamicMember keyPath: KeyPath<State, T> & Sendable) -> T {
        store[dynamicMember: keyPath]
    }

    /// Runs every service registered on the underlying store.
    ///
    /// Actions emitted by the services go through this store's ``send(_:)``, so they are recorded in
    /// the undo history with their inverse action.
    public func run() async {
        await runServices(store.services) { [self] action in
            await send(action)
        }
    }

    /// Sends an action to the store and records it in history with its inverse action.
    ///
    /// - Parameter action: The action to send
    public func send(_ action: Action) async {
        // Don't record undo/redo operations in history
        guard !isPerformingUndoRedo else {
            await store.send(action)
            return
        }

        let oldState = currentState

        // Get inverse action before applying the action
        guard let inverseAction = action.inverse(state: oldState) else {
            // If action can't be undone, just send it without recording
            await store.send(action)
            return
        }

        await store.send(action)
        let newState = currentState

        // Only record if state actually changed
        guard newState != oldState else { return }

        if isGrouping {
            // When grouping, don't add to history (group with previous action)
            isGrouping = false
        } else {
            // Record action and its inverse
            let undoableAction = UndoableAction(action: action, inverseAction: inverseAction)
            past.append(undoableAction)

            // Clear future (can't redo after new action)
            future.removeAll()

            // Apply history limit
            if historyLimit > 0, past.count > historyLimit {
                past.removeFirst(past.count - historyLimit)
            }
        }
    }

    /// Undoes the last action by dispatching its inverse action through the store.
    ///
    /// This allows middleware to intercept the inverse action and perform side effects.
    ///
    /// - Returns: `true` if undo was performed, `false` if nothing to undo
    @discardableResult
    public func undo() async -> Bool {
        guard canUndo else { return false }

        let undoableAction = past.removeLast()

        // Notify lifecycle middlewares
        await notifyLifecycle(.willUndo(action: undoableAction.action))

        // Dispatch the inverse action through the store (triggers middleware)
        isPerformingUndoRedo = true
        await store.send(undoableAction.inverseAction)
        isPerformingUndoRedo = false

        // Move to future for redo
        future.append(undoableAction)

        // Notify lifecycle middlewares
        await notifyLifecycle(.didUndo(action: undoableAction.action))

        return true
    }

    /// Redoes the last undone action by dispatching the original action through the store.
    ///
    /// This allows middleware to intercept the action and perform side effects.
    ///
    /// - Returns: `true` if redo was performed, `false` if nothing to redo
    @discardableResult
    public func redo() async -> Bool {
        guard canRedo else { return false }

        let undoableAction = future.removeLast()

        // Notify lifecycle middlewares
        await notifyLifecycle(.willRedo(action: undoableAction.action))

        // Dispatch the original action through the store (triggers middleware)
        isPerformingUndoRedo = true
        await store.send(undoableAction.action)
        isPerformingUndoRedo = false

        // Move back to past for undo
        past.append(undoableAction)

        // Notify lifecycle middlewares
        await notifyLifecycle(.didRedo(action: undoableAction.action))

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

    /// The number of actions in the undo history.
    public var undoCount: Int {
        past.count
    }

    /// The number of actions in the redo history.
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

    /// Direct access to the underlying store (use with caution).
    public var underlyingStore: Store<State, Action> {
        store
    }

    /// Gets the current state from the underlying store.
    private var currentState: State {
        store[dynamicMember: \State.self]
    }

    /// Notifies lifecycle middlewares of undo/redo events.
    private func notifyLifecycle(_ lifecycleAction: UndoRedoLifecycleAction<Action>) async {
        for middleware in lifecycleMiddlewares {
            _ = await middleware.process(state: currentState, with: lifecycleAction)
        }
    }
}

// MARK: - Derived Store

extension ActionableUndoableStore {
    /// Use this method to create another ``ActionableUndoableStore`` deriving from the current one.
    @available(*, deprecated, message: "Use multiple stores instead of derived store")
    public func derived<DerivedState: UndoableState, DerivedAction: InvertibleActionable>(
        deriveState: @Sendable @escaping (State) -> DerivedState,
        deriveAction: @Sendable @escaping (DerivedAction) -> Action
    ) -> ActionableUndoableStore<DerivedState, DerivedAction> where DerivedAction.State == DerivedState {
        let derivedStore = ActionableUndoableStore<DerivedState, DerivedAction>(
            initialState: deriveState(currentState),
            reducer: IdentityReducer(),
            middlewares: [
                ClosureMiddleware { [weak self] _, action in
                    guard let self else { return nil }

                    await self.send(deriveAction(action))
                    return nil
                }
            ],
            historyLimit: historyLimit,
            lifecycleMiddlewares: []
        )

        enableStateObservation(for: derivedStore, deriveState: deriveState)

        return derivedStore
    }

    private func enableStateObservation<DerivedState: UndoableState, DerivedAction: InvertibleActionable>(
        for derivedStore: ActionableUndoableStore<DerivedState, DerivedAction>,
        deriveState: @Sendable @escaping (State) -> DerivedState
    ) where DerivedAction.State == DerivedState {
        withObservationTracking {
            let newState = deriveState(currentState)
            if derivedStore.currentState != newState {
                derivedStore.store.setState(newState)
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

extension ActionableUndoableStore {
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
