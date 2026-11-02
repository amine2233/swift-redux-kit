import Collections
import ReduxKit

// MARK: - TreeKeyed Reducer

/// A reducer that operates on `TreeDictionary` collections.
///
/// `TreeDictionary` from Swift Collections provides an ordered dictionary that maintains
/// elements in sorted order by their keys while providing O(log n) lookups. Unlike standard
/// dictionaries which are unordered, TreeDictionary keeps elements sorted by key.
private struct TreeKeyedReducer<
    KeyedState: Hashable,
    KeyedAction: Actionable,
    State: Hashable,
    Action: Actionable,
    Key: Hashable & Comparable
>: Reducer {
    let reducer: any Reducer<State, Action>
    let keyPath: WritableKeyPath<KeyedState, TreeDictionary<Key, State>>
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

// MARK: - TreeComparableKeyed Reducer

/// A reducer that operates on `TreeDictionary` with position injection based on custom value sorting.
///
/// While `TreeDictionary` maintains elements sorted by keys, this reducer allows you to compute
/// positions based on value comparisons and inject that position back into each value. This is
/// useful for maintaining rank/position metadata while keeping efficient O(log n) key-based lookups.
private struct TreeComparableKeyedReducer<
    KeyedState: Hashable,
    KeyedAction: Actionable,
    State: Hashable,
    Action: Actionable,
    Key: Hashable & Comparable
>: Reducer {
    let reducer: any Reducer<State, Action>
    let keyPath: WritableKeyPath<KeyedState, TreeDictionary<Key, State>>
    let prism: Prism<KeyedAction, (Key, Action)>
    let comparator: @Sendable (State, State) -> Bool
    let positionInjector: @Sendable (State, Int) -> State

    func reduce(oldState: KeyedState, with action: KeyedAction) -> KeyedState {
        var oldState = oldState

        guard
            let (key, action) = prism.extract(action),
            let state = oldState[keyPath: keyPath][key]
        else {
            return oldState
        }

        let newState = reducer.reduce(oldState: state, with: action)
        var treeDictionary = oldState[keyPath: keyPath]
        treeDictionary[key] = newState

        // Sort by value comparator and inject positions
        let sortedPairs = treeDictionary.sorted { comparator($0.value, $1.value) }
        let updatedTree = TreeDictionary(
            uniqueKeysWithValues: sortedPairs.enumerated().map { index, pair in
                (pair.key, positionInjector(pair.value, index))
            }
        )

        oldState[keyPath: keyPath] = updatedTree
        return oldState
    }
}

// MARK: - TreeFilterKeyed Reducer

/// A reducer that operates on filtered elements in `TreeDictionary` collections.
///
/// This reducer applies an action to multiple elements in a TreeDictionary that match a predicate,
/// similar to `FilteredKeyedReducer` but for TreeDictionary collections. Only elements matching
/// the predicate will have the reducer applied to them.
private struct TreeFilterKeyedReducer<
    KeyedState: Hashable,
    KeyedAction: Actionable,
    State: Hashable,
    Action: Actionable,
    Key: Hashable & Comparable
>: Reducer {
    let reducer: any Reducer<State, Action>
    let keyPath: WritableKeyPath<KeyedState, TreeDictionary<Key, State>>
    let prism: Prism<KeyedAction, Action>
    let predicate: @Sendable (State) -> Bool

    func reduce(oldState: KeyedState, with action: KeyedAction) -> KeyedState {
        guard let extractedAction = prism.extract(action) else {
            return oldState
        }

        var oldState = oldState
        var treeDictionary = oldState[keyPath: keyPath]
        var hasChanges = false

        for (key, value) in treeDictionary where predicate(value) {
            let newValue = reducer.reduce(oldState: value, with: extractedAction)
            if newValue != value {
                treeDictionary[key] = newValue
                hasChanges = true
            }
        }

        if hasChanges {
            oldState[keyPath: keyPath] = treeDictionary
        }

        return oldState
    }
}

// MARK: - Reducer Extension

extension Reducer {
    /// Transforms the reducer to operate over `State` in a `TreeDictionary`.
    ///
    /// `TreeDictionary` maintains insertion order while providing efficient key-based access.
    /// This is useful when you need ordered collections with O(log n) lookups instead of
    /// the unordered nature of standard `Dictionary`.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the tree dictionary in the parent state
    ///   - prism: A prism to extract the key and action from the parent action
    ///
    /// - Returns: A reducer that operates on the parent state and action types
    ///
    /// ## Example
    /// ```swift
    /// // Maintain an ordered collection of todos
    /// let orderedTodosReducer = todoReducer.treeKeyed(
    ///     keyPath: \.todos,
    ///     prism: Prism(
    ///         extract: { action in
    ///             if case .updateTodo(let id, let action) = action {
    ///                 return (id, action)
    ///             }
    ///             return nil
    ///         },
    ///         embed: { .updateTodo($0, $1) }
    ///     )
    /// )
    /// ```
    public func treeKeyed<KeyedState: Hashable, KeyedAction: Actionable, Key: Hashable & Comparable>(
        keyPath: WritableKeyPath<KeyedState, TreeDictionary<Key, State>>,
        prism: Prism<KeyedAction, (Key, Action)>
    ) -> some Reducer<KeyedState, KeyedAction> {
        TreeKeyedReducer(reducer: self, keyPath: keyPath, prism: prism)
    }

    /// Transforms the reducer to operate over `State` in a `TreeDictionary` with position injection based on
    /// custom value sorting.
    ///
    /// While `TreeDictionary` maintains elements sorted by keys, this method allows you to compute
    /// positions based on value comparisons and inject that position back into each value. This is
    /// useful for maintaining rank/position metadata in leaderboards while keeping O(log n) key-based
    /// lookups.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the tree dictionary in the parent state
    ///   - prism: A prism to extract the key and action from the parent action
    ///   - comparator: A closure that determines the sort order of values for position calculation
    ///   - positionInjector: A closure that injects the computed position into the value
    ///
    /// - Returns: A reducer that operates on the parent state and action types
    ///
    /// ## Example
    /// ```swift
    /// // Maintain a leaderboard with rank based on score
    /// let leaderboardReducer = playerReducer.treeComparableKeyed(
    ///     keyPath: \.players,
    ///     prism: Prism(
    ///         extract: { action in
    ///             if case .updatePlayer(let id, let action) = action {
    ///                 return (id, action)
    ///             }
    ///             return nil
    ///         },
    ///         embed: { .updatePlayer($0, $1) }
    ///     ),
    ///     comparator: { $0.score > $1.score }, // Sort by descending score
    ///     positionInjector: { player, position in
    ///         var updated = player
    ///         updated.rank = position + 1 // Rank is 1-indexed
    ///         return updated
    ///     }
    /// )
    /// ```
    public func treeComparableKeyed<
        KeyedState: Hashable,
        KeyedAction: Actionable,
        Key: Hashable & Comparable
    >(
        keyPath: WritableKeyPath<KeyedState, TreeDictionary<Key, State>>,
        prism: Prism<KeyedAction, (Key, Action)>,
        comparator: @escaping @Sendable (State, State) -> Bool,
        positionInjector: @escaping @Sendable (State, Int) -> State
    ) -> some Reducer<KeyedState, KeyedAction> {
        TreeComparableKeyedReducer(
            reducer: self,
            keyPath: keyPath,
            prism: prism,
            comparator: comparator,
            positionInjector: positionInjector
        )
    }

    /// Transforms the reducer to operate over filtered `State` elements in a `TreeDictionary`.
    ///
    /// This method applies the reducer to multiple elements in the TreeDictionary that match
    /// a predicate. Only elements where the predicate returns true will be updated. The reducer
    /// is optimized to avoid unnecessary state updates when no elements match the predicate or
    /// when the reducer doesn't change any matching elements.
    ///
    /// - Parameters:
    ///   - keyPath: A writable key path to the tree dictionary in the parent state
    ///   - prism: A prism to extract the action from the parent action
    ///   - predicate: A closure that determines which elements should be updated
    ///
    /// - Returns: A reducer that operates on the parent state and action types
    ///
    /// ## Example
    /// ```swift
    /// // Bulk complete all incomplete todos in a sorted collection
    /// let todosReducer = todoReducer.treeFilterKeyed(
    ///     keyPath: \.todos,
    ///     prism: Prism(
    ///         extract: { action in
    ///             if case .bulkComplete(let action) = action {
    ///                 return action
    ///             }
    ///             return nil
    ///         },
    ///         embed: { .bulkComplete($0) }
    ///     ),
    ///     predicate: { !$0.isCompleted } // Only incomplete todos
    /// )
    /// ```
    public func treeFilterKeyed<KeyedState: Hashable, KeyedAction: Actionable, Key: Hashable & Comparable>(
        keyPath: WritableKeyPath<KeyedState, TreeDictionary<Key, State>>,
        prism: Prism<KeyedAction, Action>,
        predicate: @escaping @Sendable (State) -> Bool
    ) -> some Reducer<KeyedState, KeyedAction> {
        TreeFilterKeyedReducer(reducer: self, keyPath: keyPath, prism: prism, predicate: predicate)
    }
}
