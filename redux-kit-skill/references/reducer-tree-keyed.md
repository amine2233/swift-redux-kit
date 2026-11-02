---
name: reducer-tree-keyed
description: Guide to .treeKeyed(), .treeComparableKeyed(), and .treeFilterKeyed() — reducer variants for TreeDictionary<Key, State> from swift-collections, providing O(log n) key-sorted storage with single-entry, rank-injecting, and predicate-batch variants.
---

# `TreeDictionary` Reducers — `treeKeyed`, `treeComparableKeyed`, `treeFilterKeyed`

These three reducer extensions from **`ReduxKitExtensions`** mirror the standard `[Key: State]` reducers but operate on `TreeDictionary<Key, State>` from the [swift-collections](https://github.com/apple/swift-collections) package.

> **Module:** `import ReduxKitExtensions` is required. These extensions are **not** in the core `ReduxKit` module.

---

## Why `TreeDictionary`?

| | `[Key: State]` | `TreeDictionary<Key, State>` |
|---|---|---|
| Key lookup | O(1) average | O(log n) |
| Iteration order | Undefined | Always sorted by `Key` (ascending) |
| Key constraint | `Hashable` | `Hashable & Comparable` |
| Use case | Unordered keyed state | Ordered keyed state (menus, leaderboards, sorted lists) |

Use `TreeDictionary` when the sorted-by-key order matters for display or iteration, and you still need fast key-based access.

---

## The Three Variants

| Method | Prism target | After reduce | Use case |
|--------|--------------|--------------|----------|
| `.treeKeyed()` | `(Key, ChildAction)` | Single entry updated | Single-item interaction in ordered collection |
| `.treeComparableKeyed()` | `(Key, ChildAction)` | Single entry updated, all values re-ranked | Leaderboards — rank metadata in every value |
| `.treeFilterKeyed()` | `ChildAction` (no key) | All matching values updated | Bulk operations on subset of ordered collection |

---

## Setup

Add `swift-collections` to your `Package.swift` if not already present:

```swift
.package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0")
```

And add `ReduxKitExtensions` to your target dependencies.

---

## `.treeKeyed()` — Single Entry in an Ordered Collection

Works exactly like `.keyed()` but targets `TreeDictionary<Key, State>`. The key must conform to `Hashable & Comparable`.

### Anatomy

```
ParentState
  └── todos: TreeDictionary<Int, TodoItem>   ← keyPath points here

ParentAction
  └── case updateTodo(Int, TodoAction)        ← prism extracts (Int, TodoAction)
```

### Example

```swift
struct TodoReducer: Reducer {
    struct State: Hashable, Identifiable {
        var id: Int
        var title: String
        var isCompleted: Bool
    }

    enum Action: Actionable {
        case toggle
        case setTitle(String)
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .toggle:               state.isCompleted.toggle()
        case let .setTitle(title):  state.title = title
        }
        return state
    }
}

struct AppReducer: Reducer {
    struct State: Hashable {
        var todos: TreeDictionary<Int, TodoReducer.State> = [:]
    }

    enum Action: Actionable {
        case updateTodo(Int, TodoReducer.Action)

        static let prism = Prism<Self, (Int, TodoReducer.Action)>(
            embed: { .updateTodo($0, $1) },
            extract: {
                guard case let .updateTodo(id, action) = $0 else { return nil }
                return (id, action)
            }
        )
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .updateTodo:
            break   // handled by .treeKeyed() below
        }
        return TodoReducer()
            .treeKeyed(keyPath: \.todos, prism: Action.prism)
            .reduce(oldState: state, with: action)
    }
}
```

### Dispatching

```swift
store.dispatch(.updateTodo(42, .toggle))
store.dispatch(.updateTodo(7, .setTitle("New title")))
```

---

## `.treeComparableKeyed()` — Single Entry with Value-based Rank Injection

Extends `.treeKeyed()` with two extra closures:

- **`comparator`**: determines which value is "higher" (used to rank values by score, priority, etc.)
- **`positionInjector`**: called on every value after sorting, receives the value and its 0-based rank, returns a copy with rank injected

After every single-entry update the entire dictionary is re-ranked and the rank field in each value is updated. The `TreeDictionary` is keyed by the original key — stable key-based access is preserved.

### Anatomy

```
ParentState
  └── players: TreeDictionary<Int, Player>     ← keyPath points here

ParentAction
  └── case updatePlayer(Int, PlayerAction)      ← prism extracts (Int, PlayerAction)

comparator: (Player, Player) -> Bool            ← value-based sort order
positionInjector: (Player, Int) -> Player       ← injects 0-based rank into every player
```

### Example — Leaderboard

```swift
struct PlayerReducer: Reducer {
    struct State: Hashable, Identifiable {
        var id: Int
        var name: String
        var score: Int
        var level: Int
        var rank: Int = 0   // populated by positionInjector
    }

    enum Action: Actionable {
        case addPoints(Int)
        case levelUp
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case let .addPoints(pts): state.score += pts
        case .levelUp:            state.level += 1
        }
        return state
    }
}

struct LeaderboardReducer: Reducer {
    struct State: Hashable {
        var players: TreeDictionary<Int, PlayerReducer.State> = [:]
    }

    enum Action: Actionable {
        case updatePlayer(Int, PlayerReducer.Action)

        static let prism = Prism<Self, (Int, PlayerReducer.Action)>(
            embed: { .updatePlayer($0, $1) },
            extract: {
                guard case let .updatePlayer(id, action) = $0 else { return nil }
                return (id, action)
            }
        )
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .updatePlayer:
            break   // handled by .treeComparableKeyed() below
        }
        return PlayerReducer()
            .treeComparableKeyed(
                keyPath: \.players,
                prism: Action.prism,
                comparator: { $0.score > $1.score },        // rank by score descending
                positionInjector: { player, position in
                    var p = player
                    p.rank = position + 1                   // 0-based → 1-based rank
                    return p
                }
            )
            .reduce(oldState: state, with: action)
    }
}
```

### Multi-criteria Comparator

```swift
comparator: { lhs, rhs in
    if lhs.level != rhs.level { return lhs.level > rhs.level }
    return lhs.score > rhs.score    // tie-break within same level
}
```

### Dispatching

```swift
store.dispatch(.updatePlayer(1, .addPoints(150)))
store.dispatch(.updatePlayer(3, .levelUp))
```

After either dispatch, every `Player.rank` in the dictionary reflects the updated leaderboard.

---

## `.treeFilterKeyed()` — Predicate-filtered Batch on Ordered Collection

Works like `.filteredKeyed()` but targets `TreeDictionary`. The prism extracts only `ChildAction` (no key). The reducer is applied to every value that satisfies the predicate.

Internally optimised: only writes back to the dictionary when at least one value actually changed.

### Anatomy

```
ParentState
  └── tasks: TreeDictionary<Int, Task>    ← keyPath points here

ParentAction
  └── case bulkComplete(TaskAction)        ← prism extracts TaskAction (no key)

predicate: (Task) -> Bool                 ← decides which values receive the action
```

### Example

```swift
struct TaskReducer: Reducer {
    struct State: Hashable, Identifiable {
        var id: Int
        var title: String
        var isCompleted: Bool
        var priority: Int
    }

    enum Action: Actionable {
        case complete
        case increasePriority
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .complete:         state.isCompleted = true
        case .increasePriority: state.priority += 1
        }
        return state
    }
}

struct TaskListReducer: Reducer {
    struct State: Hashable {
        var tasks: TreeDictionary<Int, TaskReducer.State> = [:]
    }

    enum Action: Actionable {
        case bulkComplete(TaskReducer.Action)
        case bulkIncreasePriority(TaskReducer.Action)
    }
}

extension TaskListReducer.Action {
    static let completePrism = Prism<Self, TaskReducer.Action>(
        embed: { .bulkComplete($0) },
        extract: {
            guard case let .bulkComplete(action) = $0 else { return nil }
            return action
        }
    )

    static let priorityPrism = Prism<Self, TaskReducer.Action>(
        embed: { .bulkIncreasePriority($0) },
        extract: {
            guard case let .bulkIncreasePriority(action) = $0 else { return nil }
            return action
        }
    )
}

extension TaskListReducer {
    func reduce(oldState: State, with action: Action) -> State {
        CombinedReducer(reducers: [
            // Complete all incomplete tasks
            TaskReducer()
                .treeFilterKeyed(
                    keyPath: \.tasks,
                    prism: Action.completePrism,
                    predicate: { !$0.isCompleted }
                ),
            // Boost priority of all high-priority tasks
            TaskReducer()
                .treeFilterKeyed(
                    keyPath: \.tasks,
                    prism: Action.priorityPrism,
                    predicate: { $0.priority > 5 }
                ),
        ]).reduce(oldState: oldState, with: action)
    }
}
```

### Dispatching

```swift
store.dispatch(.bulkComplete(.complete))
store.dispatch(.bulkIncreasePriority(.increasePriority))
```

---

## Choosing Between Standard and Tree Variants

| Goal | Standard variant | Tree variant |
|------|-----------------|--------------|
| Single-entry, unordered dict | `.keyed()` | `.treeKeyed()` |
| Single-entry + rank in values | `.comparableOffset()` (array) | `.treeComparableKeyed()` |
| Batch predicate, unordered dict | `.filteredKeyed()` | `.treeFilterKeyed()` |
| Access by stable ID, no rank needed | `.keyed()` | `.treeKeyed()` |
| Iteration must be key-sorted | — | `.treeKeyed()` / `.treeFilterKeyed()` |
| Rank stored in value, keyed access | — | `.treeComparableKeyed()` |

> **Prefer `.treeKeyed()` / `.treeFilterKeyed()` over their standard `[Key: State]`** when you need the
> dictionary to iterate in a deterministic, key-sorted order — for example, when the key is a date,
> numeric ID, or any `Comparable` type whose natural order matches the display order.
