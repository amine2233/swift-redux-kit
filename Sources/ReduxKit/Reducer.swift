import Foundation

// swiftlint:disable file_length
// Cohesive unit: the Reducer protocol plus its composition helpers and their `private`-backed
// reducer types. Splitting would scatter tightly-coupled implementation across files for no gain.

/// A protocol that defines how state mutations occur in response to actions.
///
/// Reducers are pure functions that produce a new state by applying an action to the current state.
/// They form the core of state mutation logic in a unidirectional data flow architecture.
public protocol Reducer<State, Action> {
    /// The type of state this reducer operates on.
    associatedtype State: Hashable
    /// The type of action this reducer handles.
    associatedtype Action: Actionable

    /// The function returning a new state by taking an old state and an action.
    func reduce(oldState: State, with action: Action) -> State
}

/// A type conforming to the ``Reducer`` protocol that doesn't apply any mutation to the old state.
public struct IdentityReducer<State: Hashable, Action: Actionable>: Reducer {
    package init() {}

    public func reduce(oldState: State, with action: Action) -> State {
        oldState
    }
}

/// The type of ``Reducer`` combining a `Collection` of reducers into one instance.
public struct CombinedReducer<State: Hashable, Action: Actionable>: Reducer {
    let reducers: any Collection<any Reducer<State, Action>>

    public init(reducers: any Reducer<State, Action>...) {
        self.reducers = reducers
    }

    public init(reducers: some Collection<any Reducer<State, Action>>) {
        self.reducers = reducers
    }

    public func reduce(oldState: State, with action: Action) -> State {
        reducers.reduce(oldState) {
            $1.reduce(oldState: $0, with: action)
        }
    }
}

private struct LiftedReducer<
    LiftedState: Hashable,
    LiftedAction: Actionable,
    LoweredState: Hashable,
    LoweredAction: Actionable
>: Reducer {
    typealias State = LiftedState
    typealias Action = LiftedAction

    let reducer: any Reducer<LoweredState, LoweredAction>
    let keyPath: WritableKeyPath<LiftedState, LoweredState>
    let prism: Prism<LiftedAction, LoweredAction>

    func reduce(oldState: State, with action: Action) -> State {
        guard let loweredAction = prism.extract(action) else {
            return oldState
        }

        var oldState = oldState

        oldState[keyPath: keyPath] = reducer.reduce(
            oldState: oldState[keyPath: keyPath],
            with: loweredAction
        )

        return oldState
    }
}

private struct OptionalReducer<UnwrappedState: Hashable, Action: Actionable>: Reducer {
    typealias State = UnwrappedState?

    let reducer: any Reducer<UnwrappedState, Action>

    func reduce(oldState: State, with action: Action) -> State {
        oldState.map { reducer.reduce(oldState: $0, with: action) } ?? oldState
    }
}

private struct KeyedReducer<
    KeyedState: Hashable,
    KeyedAction: Actionable,
    State: Hashable,
    Action: Actionable,
    Key: Hashable
>: Reducer {
    let reducer: any Reducer<State, Action>

    let keyPath: WritableKeyPath<KeyedState, [Key: State]>
    let prism: Prism<KeyedAction, (Key, Action)>

    func reduce(oldState: KeyedState, with action: KeyedAction) -> KeyedState {
        var oldState = oldState

        guard
            let (key, action) = prism.extract(action),
            let state = oldState[keyPath: keyPath][key]
        else {
            return oldState
        }

        let newState = reducer.reduce(oldState: state, with: action)
        oldState[keyPath: keyPath][key] = newState

        return oldState
    }
}

private struct OffsetReducer<
    IndexedState: Hashable,
    IndexedAction: Actionable,
    State: Hashable,
    Action: Actionable
>: Reducer {
    let reducer: any Reducer<State, Action>

    let keyPath: WritableKeyPath<IndexedState, [State]>
    let prism: Prism<IndexedAction, (Int, Action)>

    func reduce(oldState: IndexedState, with action: IndexedAction) -> IndexedState {
        guard
            let (index, action) = prism.extract(action),
            oldState[keyPath: keyPath].indices.contains(index)
        else {
            return oldState
        }

        var oldState = oldState
        let newState = reducer.reduce(
            oldState: oldState[keyPath: keyPath][index],
            with: action
        )
        oldState[keyPath: keyPath][index] = newState
        return oldState
    }
}

private struct FilterOffsetReducer<
    IndexedState: Hashable,
    IndexedAction: Actionable,
    State: Hashable,
    Action: Actionable
>: Reducer {
    let reducer: any Reducer<State, Action>
    let keyPath: WritableKeyPath<IndexedState, [State]>
    let prism: Prism<IndexedAction, Action>
    let predicate: @Sendable (State) -> Bool

    func reduce(oldState: IndexedState, with action: IndexedAction) -> IndexedState {
        guard let extractedAction = prism.extract(action) else {
            return oldState
        }

        var oldState = oldState
        var array = oldState[keyPath: keyPath]
        var hasChanges = false

        // Apply reducer only to elements that match the predicate
        for (index, element) in array.enumerated() where predicate(element) {
            let newElement = reducer.reduce(oldState: element, with: extractedAction)
            if newElement != element {
                array[index] = newElement
                hasChanges = true
            }
        }

        // Only update the state if something actually changed
        if hasChanges {
            oldState[keyPath: keyPath] = array
        }

        return oldState
    }
}

private struct FilteredKeyedReducer<
    KeyedState: Hashable,
    KeyedAction: Actionable,
    State: Hashable,
    Action: Actionable,
    Key: Hashable
>: Reducer {
    let reducer: any Reducer<State, Action>
    let keyPath: WritableKeyPath<KeyedState, [Key: State]>
    let prism: Prism<KeyedAction, Action>
    let predicate: @Sendable (State) -> Bool

    func reduce(oldState: KeyedState, with action: KeyedAction) -> KeyedState {
        guard let extractedAction = prism.extract(action) else {
            return oldState
        }

        var oldState = oldState
        var dictionary = oldState[keyPath: keyPath]
        var hasChanges = false

        // Apply reducer only to values that match the predicate
        for (key, value) in dictionary where predicate(value) {
            let newValue = reducer.reduce(oldState: value, with: extractedAction)
            if newValue != value {
                dictionary[key] = newValue
                hasChanges = true
            }
        }

        // Only update the state if something actually changed
        if hasChanges {
            oldState[keyPath: keyPath] = dictionary
        }

        return oldState
    }
}

private struct SortedOffsetReducer<
    IndexedState: Hashable,
    IndexedAction: Actionable,
    State: Hashable,
    Action: Actionable
>: Reducer {
    let reducer: any Reducer<State, Action>
    let keyPath: WritableKeyPath<IndexedState, [State]>
    let prism: Prism<IndexedAction, (Int, Action)>
    let comparator: @Sendable (State, State) -> Bool

    func reduce(oldState: IndexedState, with action: IndexedAction) -> IndexedState {
        guard
            let (index, action) = prism.extract(action),
            oldState[keyPath: keyPath].indices.contains(index)
        else {
            return oldState
        }

        var oldState = oldState
        var array = oldState[keyPath: keyPath]

        // Apply the reducer to the element at the given index
        let newElement = reducer.reduce(
            oldState: array[index],
            with: action
        )
        array[index] = newElement

        // Sort the array using the comparator
        array.sort(by: comparator)

        oldState[keyPath: keyPath] = array
        return oldState
    }
}

private struct ComparableOffsetReducer<
    IndexedState: Hashable,
    IndexedAction: Actionable,
    State: Hashable,
    Action: Actionable
>: Reducer {
    let reducer: any Reducer<State, Action>
    let keyPath: WritableKeyPath<IndexedState, [State]>
    let prism: Prism<IndexedAction, (Int, Action)>
    let comparator: @Sendable (State, State) -> Bool
    let positionInjector: @Sendable (State, Int) -> State

    func reduce(oldState: IndexedState, with action: IndexedAction) -> IndexedState {
        guard
            let (index, action) = prism.extract(action),
            oldState[keyPath: keyPath].indices.contains(index)
        else {
            return oldState
        }

        var oldState = oldState
        var array = oldState[keyPath: keyPath]

        // Apply the reducer to the element at the given index
        let newElement = reducer.reduce(
            oldState: array[index],
            with: action
        )
        array[index] = newElement

        // Sort by comparator and inject positions
        let sortedArray = array.sorted(by: comparator)
        let updatedArray = sortedArray.enumerated().map { index, element in
            positionInjector(element, index)
        }

        oldState[keyPath: keyPath] = updatedArray
        return oldState
    }
}

extension Reducer {
    /// Transforms the reducer to operate over `State` wrapped into another type.
    public func lifted<LiftedState: Hashable, LiftedAction: Actionable>(
        keyPath: WritableKeyPath<LiftedState, State>,
        prism: Prism<LiftedAction, Action>
    ) -> some Reducer<LiftedState, LiftedAction> {
        LiftedReducer(reducer: self, keyPath: keyPath, prism: prism)
    }

    /// Transforms the reducer to operate over `State` in a `Dictionary`.
    public func keyed<KeyedState: Hashable, KeyedAction: Actionable, Key: Hashable>(
        keyPath: WritableKeyPath<KeyedState, [Key: State]>,
        prism: Prism<KeyedAction, (Key, Action)>
    ) -> some Reducer<KeyedState, KeyedAction> {
        KeyedReducer(reducer: self, keyPath: keyPath, prism: prism)
    }

    /// Transforms the reducer to operate over `State``State` in an `Array`.
    public func offset<OffsetState: Hashable, OffsetAction: Actionable>(
        keyPath: WritableKeyPath<OffsetState, [State]>,
        prism: Prism<OffsetAction, (Int, Action)>
    ) -> some Reducer<OffsetState, OffsetAction> {
        OffsetReducer(reducer: self, keyPath: keyPath, prism: prism)
    }

    /// Transforms the reducer to operate over filtered elements in an `Array`.
    ///
    /// This reducer applies the action to all elements in the array that match the given predicate.
    /// Useful for batch operations on filtered subsets of data.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the array in the parent state
    ///   - prism: A prism to extract the action from the parent action
    ///   - predicate: A closure that determines which elements should be updated
    ///
    /// - Returns: A reducer that operates on the parent state and action types
    ///
    /// ## Example
    /// ```swift
    /// // Apply action to all completed tasks
    /// let completedTasksReducer = taskReducer.filterOffset(
    ///     keyPath: \.tasks,
    ///     prism: Prism(
    ///         extract: { action in
    ///             if case .updateCompleted(let action) = action { return action }
    ///             return nil
    ///         },
    ///         embed: { .updateCompleted($0) }
    ///     ),
    ///     predicate: { $0.isCompleted }
    /// )
    /// ```
    public func filterOffset<OffsetState: Hashable, OffsetAction: Actionable>(
        keyPath: WritableKeyPath<OffsetState, [State]>,
        prism: Prism<OffsetAction, Action>,
        predicate: @escaping @Sendable (State) -> Bool
    ) -> some Reducer<OffsetState, OffsetAction> {
        FilterOffsetReducer(
            reducer: self,
            keyPath: keyPath,
            prism: prism,
            predicate: predicate
        )
    }

    /// Transforms the reducer to operate over filtered values in a `Dictionary`.
    ///
    /// This reducer applies the action to all dictionary values that match the given predicate.
    /// Useful for batch operations on filtered subsets of keyed data.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the dictionary in the parent state
    ///   - prism: A prism to extract the action from the parent action
    ///   - predicate: A closure that determines which values should be updated
    ///
    /// - Returns: A reducer that operates on the parent state and action types
    ///
    /// ## Example
    /// ```swift
    /// // Apply action to all completed todos
    /// let completedTodosReducer = todoReducer.filteredKeyed(
    ///     keyPath: \.todos,
    ///     prism: Prism(
    ///         extract: { action in
    ///             if case .updateCompleted(let action) = action { return action }
    ///             return nil
    ///         },
    ///         embed: { .updateCompleted($0) }
    ///     ),
    ///     predicate: { $0.isCompleted }
    /// )
    /// ```
    public func filteredKeyed<KeyedState: Hashable, KeyedAction: Actionable, Key: Hashable>(
        keyPath: WritableKeyPath<KeyedState, [Key: State]>,
        prism: Prism<KeyedAction, Action>,
        predicate: @escaping @Sendable (State) -> Bool
    ) -> some Reducer<KeyedState, KeyedAction> {
        FilteredKeyedReducer(
            reducer: self,
            keyPath: keyPath,
            prism: prism,
            predicate: predicate
        )
    }

    /// Transforms the reducer to operate over a sorted `Array`.
    ///
    /// This reducer applies the action to an element at a specific index and then re-sorts
    /// the entire array using the provided comparator. Useful for maintaining sorted lists
    /// where updates might change the sort order.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the array in the parent state
    ///   - prism: A prism to extract the index and action from the parent action
    ///   - comparator: A closure that determines the sort order
    ///
    /// - Returns: A reducer that operates on the parent state and action types
    ///
    /// ## Example
    /// ```swift
    /// // Maintain a sorted task list by priority
    /// let sortedTaskReducer = taskReducer.sortedOffset(
    ///     keyPath: \.tasks,
    ///     prism: Prism(
    ///         extract: { action in
    ///             if case .updateTask(let index, let action) = action {
    ///                 return (index, action)
    ///             }
    ///             return nil
    ///         },
    ///         embed: { .updateTask($0, $1) }
    ///     ),
    ///     comparator: { $0.priority > $1.priority } // Sort by priority descending
    /// )
    /// ```
    public func sortedOffset<OffsetState: Hashable, OffsetAction: Actionable>(
        keyPath: WritableKeyPath<OffsetState, [State]>,
        prism: Prism<OffsetAction, (Int, Action)>,
        comparator: @escaping @Sendable (State, State) -> Bool
    ) -> some Reducer<OffsetState, OffsetAction> {
        SortedOffsetReducer(
            reducer: self,
            keyPath: keyPath,
            prism: prism,
            comparator: comparator
        )
    }

    /// Transforms the reducer to operate over `State` in an `Array` with position injection based on custom
    /// sorting.
    ///
    /// This method applies the reducer to an element at a given index, then sorts the array using a custom
    /// comparator and injects the computed position back into each element. This is useful for maintaining
    /// rank/position metadata in sorted arrays (e.g., leaderboards, priority lists).
    ///
    /// ## How it works
    ///
    /// 1. Applies the reducer to the element at the specified index
    /// 2. Sorts the entire array using the `comparator` closure
    /// 3. Iterates through the sorted array and calls `positionInjector` for each element
    /// 4. The `positionInjector` receives:
    ///    - The element (after reducer was applied)
    ///    - Its position in the sorted array (0-indexed)
    /// 5. Returns a modified copy of the element with position metadata injected
    ///
    /// ## About positionInjector
    ///
    /// The `positionInjector` closure allows you to inject position/rank metadata into your state values.
    /// It receives two parameters:
    /// - `element`: The current state element (e.g., a Player)
    /// - `position`: The 0-based index in the sorted array (0 = first place, 1 = second place, etc.)
    ///
    /// You typically use this to:
    /// - Set a `rank` property (converting 0-based to 1-based: `position + 1`)
    /// - Store the sort position for UI display
    /// - Update any position-dependent metadata in your state
    ///
    /// The injector must return a modified copy of the element with the position data added.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the array in the parent state
    ///   - prism: A prism to extract the index and action from the parent action
    ///   - comparator: A closure that determines the sort order (e.g., `{ $0.score > $1.score }`)
    ///   - positionInjector: A closure `(State, Int) -> State` that receives each element and its
    ///                       0-based position in the sorted array, returning a copy with position injected
    ///
    /// - Returns: A reducer that operates on the parent state and action types
    ///
    /// ## Example
    /// ```swift
    /// struct Player: Hashable {
    ///     var name: String
    ///     var score: Int
    ///     var rank: Int = 0  // Position metadata
    /// }
    ///
    /// // Maintain a leaderboard with automatic rank updates
    /// let leaderboardReducer = playerReducer.comparableOffset(
    ///     keyPath: \.players,
    ///     prism: Prism(
    ///         extract: { action in
    ///             if case .updatePlayer(let index, let action) = action {
    ///                 return (index, action)
    ///             }
    ///             return nil
    ///         },
    ///         embed: { .updatePlayer($0, $1) }
    ///     ),
    ///     comparator: { $0.score > $1.score }, // Sort by descending score
    ///     positionInjector: { player, position in
    ///         // position is 0-based: 0, 1, 2, ...
    ///         // Convert to 1-based rank: 1, 2, 3, ...
    ///         var updated = player
    ///         updated.rank = position + 1
    ///         return updated
    ///     }
    /// )
    /// ```
    ///
    /// After an update, players are automatically sorted by score and each player's `rank` property
    /// reflects their position in the leaderboard (1 = first place, 2 = second place, etc.).
    public func comparableOffset<OffsetState: Hashable, OffsetAction: Actionable>(
        keyPath: WritableKeyPath<OffsetState, [State]>,
        prism: Prism<OffsetAction, (Int, Action)>,
        comparator: @escaping @Sendable (State, State) -> Bool,
        positionInjector: @escaping @Sendable (State, Int) -> State
    ) -> some Reducer<OffsetState, OffsetAction> {
        ComparableOffsetReducer(
            reducer: self,
            keyPath: keyPath,
            prism: prism,
            comparator: comparator,
            positionInjector: positionInjector
        )
    }

    /// Transforms the reducer to operate over `Optional<State>`.
    public func optional() -> some Reducer<State?, Action> {
        OptionalReducer(reducer: self)
    }
}
