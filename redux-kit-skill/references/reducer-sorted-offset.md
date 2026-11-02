---
name: reducer-sorted-offset
description: Guide to .sortedOffset(keyPath:prism:comparator:) — applying a reducer to a single array element by index, then re-sorting the entire array with a comparator, keeping sorted lists consistent after mutations.
---

# `.sortedOffset()` — Index-targeted Reducer with Auto-sort

`.sortedOffset(keyPath:prism:comparator:)` lifts a feature reducer so it operates on **one element in a `[State]` array by its integer index**, then **re-sorts the entire array** using the provided comparator.
This keeps a sorted list consistent after any mutation that might change the element's sort position.

> **Reducer only** — there is no middleware equivalent of `.sortedOffset()`.

---

## How It Differs from `.offset()`

| | `.offset()` | `.sortedOffset()` |
|---|---|---|
| Target | One element by **index** | One element by **index** |
| Prism target | `(Int, ChildAction)` | `(Int, ChildAction)` |
| After reduce | Array unchanged | Array re-sorted by comparator |
| Use case | Element mutation, order preserved | Element mutation in a sorted list |

> **Use `.offset()` when order is positional.** Use `.sortedOffset()` when the array must remain sorted by some property (priority, date, name, etc.) even after mutations.

---

## Anatomy

```
ParentState
  └── tasks: [Task]                          ← keyPath points here

ParentAction
  └── case updateTask(Int, TaskAction)        ← prism extracts (Int, TaskAction)

comparator: (Task, Task) -> Bool              ← defines sort order after each reduce

TaskReducer operates on Task with TaskAction
```

---

## 1. Define the Element Reducer

The element reducer is unaware it operates inside a sorted array.

```swift
struct TaskReducer: Reducer {
    struct State: Hashable {
        var id: Int
        var title: String
        var priority: Int
    }

    enum Action: Actionable {
        case increasePriority
        case decreasePriority
        case setPriority(Int)
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .increasePriority:    state.priority += 1
        case .decreasePriority:    state.priority -= 1
        case let .setPriority(p):  state.priority = p
        }
        return state
    }
}
```

---

## 2. Define the Parent State & Action

The parent action case carries both the **index** and the **child action** — the same shape as `.offset()`.

```swift
struct AppReducer: Reducer {
    struct State: Hashable {
        var tasks: [TaskReducer.State] = []
    }

    enum Action: Actionable {
        case updateTask(Int, TaskReducer.Action)
    }
}
```

---

## 3. Define the Prism

The prism target is `(Int, ChildAction)` — identical to the `.offset()` prism.

```swift
extension AppReducer.Action {
    static let updateTaskPrism = Prism<AppReducer.Action, (Int, TaskReducer.Action)>(
        embed: { AppReducer.Action.updateTask($0, $1) },
        extract: {
            guard case let .updateTask(index, action) = $0 else { return nil }
            return (index, action)
        }
    )
}
```

---

## 4. Parent Reducer — Use `.sortedOffset()` with a Comparator

Pass the comparator that defines the desired sort order. It is re-applied after every mutation.

```swift
extension AppReducer {
    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState

        switch action {
        case .updateTask:
            break   // handled by .sortedOffset() below
        }

        return TaskReducer()
            .sortedOffset(
                keyPath: \.tasks,
                prism: Action.updateTaskPrism,
                comparator: { $0.priority > $1.priority }   // highest priority first
            )
            .reduce(oldState: state, with: action)
    }
}
```

`.sortedOffset()` automatically:

1. Extracts `(index, ChildAction)` using the prism — returns unchanged state if prism yields `nil`.
2. Returns unchanged state if the index is out of bounds.
3. Applies the element reducer to `array[index]`.
4. Re-sorts the entire array using the comparator.
5. Writes the sorted array back to the key path.

> **Note on stability:** Swift's `Array.sort(by:)` is not guaranteed to be stable. If two elements compare equal, their relative order may change. Use a tie-breaking secondary sort key (e.g., `id`) when stable ordering matters:
>
> ```swift
> comparator: { lhs, rhs in
>     lhs.priority != rhs.priority
>         ? lhs.priority > rhs.priority
>         : lhs.id < rhs.id
> }
> ```

---

## 5. Combining with Other Reducers

Use `CombinedReducer` when one action should also trigger other logic alongside the sorted update.

```swift
return CombinedReducer(reducers: [
    TaskReducer()
        .sortedOffset(
            keyPath: \.tasks,
            prism: Action.updateTaskPrism,
            comparator: { $0.priority > $1.priority }
        ),
    AppMetaReducer()
        .lifted(keyPath: \.meta, prism: Action.metaPrism),
]).reduce(oldState: state, with: action)
```

---

## 6. Dispatching from the View

The dispatch shape is the same as `.offset()` — pass the current index of the element.

```swift
// Increase priority of the task currently at index 2
store.dispatch(.updateTask(2, .increasePriority))

// Set a specific priority for the task at index 0
store.dispatch(.updateTask(0, .setPriority(10)))
```

> **Index fragility warning:** After a dispatch, the array is re-sorted and indices shift. Never cache an index across multiple dispatches — always derive the current index from the sorted array at dispatch time.

---

## When NOT to Use `.sortedOffset()`

| Situation | Better approach |
|-----------|-----------------|
| List is unordered or order is positional | `.offset(keyPath:prism:)` |
| State is stored as `[Key: State]` dictionary | `.keyed(keyPath:prism:)` |
| All elements must be re-sorted without targeting one | Loop in the parent reducer, call `sort(by:)` directly |
| Bulk update matching a predicate before sorting | `.filterOffset()` in the parent, then sort manually |
