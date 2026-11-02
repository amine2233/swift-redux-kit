---
name: reducer-filter-offset
description: Guide to .filterOffset(keyPath:prism:predicate:) — applying a reducer action to all array elements that match a predicate, enabling batch operations on filtered subsets.
---

# `.filterOffset()` — Predicate-filtered Batch Reducer

`.filterOffset(keyPath:prism:predicate:)` lifts a feature reducer so it applies an action to **every element in an array that satisfies a predicate**.
Unlike `.offset()` which targets one element by index, `filterOffset` is a bulk operation — it touches zero, one, or many elements in a single reduce call.

> **Reducer only** — there is no middleware equivalent of `.filterOffset()`.

---

## How It Differs from `.offset()`

| | `.offset()` | `.filterOffset()` |
|---|---|---|
| Target | One element by **index** | All elements matching a **predicate** |
| Prism target | `(Int, ChildAction)` | `ChildAction` (no index) |
| Elements modified | Exactly one (or zero if out of bounds) | Zero or more |
| Use case | Single-item interaction | Batch/bulk operations |

---

## Anatomy

```
ParentState
  └── tasks: [Task]                ← keyPath points here

ParentAction
  └── case completeWork(TaskAction) ← prism extracts TaskAction (no index)

predicate: (Task) -> Bool           ← decides which elements receive the action

TaskReducer operates on Task with TaskAction
```

---

## 1. Define the Element Reducer

The element reducer is unaware it will be used in a batch context.

```swift
struct TaskReducer: Reducer {
    struct State: Hashable {
        var id: String
        var title: String
        var isCompleted: Bool
        var category: String
        var priority: Priority

        enum Priority: String, Hashable { case low, medium, high }
    }

    enum Action: Actionable {
        case complete
        case uncomplete
        case toggle
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .complete:   state.isCompleted = true
        case .uncomplete: state.isCompleted = false
        case .toggle:     state.isCompleted.toggle()
        }
        return state
    }
}
```

---

## 2. Define the Parent State & Action

Each bulk operation gets its own action case. The prism for `filterOffset` extracts only `ChildAction` — no index.

```swift
struct AppReducer: Reducer {
    struct State: Hashable {
        var tasks: [TaskReducer.State] = []
    }

    enum Action: Actionable {
        case completeByCategory(String, TaskReducer.Action)
        case completeByPriority(TaskReducer.State.Priority, TaskReducer.Action)
        case toggleCompleted(TaskReducer.Action)
    }
}
```

---

## 3. Static Prism (Fixed Filter)

Use a `static let` prism when the filter criterion is the same for every dispatch.

```swift
extension AppReducer.Action {
    // Prism for actions targeting currently-completed tasks
    static let completedPrism = Prism<AppReducer.Action, TaskReducer.Action>(
        embed: { AppReducer.Action.toggleCompleted($0) },
        extract: {
            guard case let .toggleCompleted(action) = $0 else { return nil }
            return action
        }
    )
}
```

Usage in the reducer:

```swift
case .toggleCompleted:
    return TaskReducer()
        .filterOffset(
            keyPath: \.tasks,
            prism: Action.completedPrism,
            predicate: { $0.isCompleted }
        )
        .reduce(oldState: state, with: action)
```

---

## 4. Dynamic Prism (Parametric Filter)

Use a factory function when the criterion is carried inside the action (e.g. a category name or priority level).

```swift
extension AppReducer {
    static func categoryPrism(for category: String) -> Prism<Action, TaskReducer.Action> {
        .init(
            embed: { Action.completeByCategory(category, $0) },
            extract: {
                guard case let .completeByCategory(cat, action) = $0, cat == category else {
                    return nil
                }
                return action
            }
        )
    }

    static func priorityPrism(for priority: TaskReducer.State.Priority) -> Prism<Action, TaskReducer.Action> {
        .init(
            embed: { Action.completeByPriority(priority, $0) },
            extract: {
                guard case let .completeByPriority(pri, action) = $0, pri == priority else {
                    return nil
                }
                return action
            }
        )
    }
}
```

Usage in the reducer:

```swift
func reduce(oldState: State, with action: Action) -> State {
    var state = oldState

    switch action {
    case let .completeByCategory(category, _):
        return TaskReducer()
            .filterOffset(
                keyPath: \.tasks,
                prism: Self.categoryPrism(for: category),
                predicate: { $0.category == category }
            )
            .reduce(oldState: state, with: action)

    case let .completeByPriority(priority, _):
        return TaskReducer()
            .filterOffset(
                keyPath: \.tasks,
                prism: Self.priorityPrism(for: priority),
                predicate: { $0.priority == priority }
            )
            .reduce(oldState: state, with: action)

    case .toggleCompleted:
        return TaskReducer()
            .filterOffset(
                keyPath: \.tasks,
                prism: Action.completedPrism,
                predicate: { $0.isCompleted }
            )
            .reduce(oldState: state, with: action)
    }
}
```

---

## 5. Combining Multiple `filterOffset` Reducers

Use `CombinedReducer` when a single action should trigger different bulk operations simultaneously.

```swift
func reduce(oldState: State, with action: Action) -> State {
    CombinedReducer(reducers: [
        TaskReducer()
            .filterOffset(
                keyPath: \.tasks,
                prism: Action.completedPrism,
                predicate: { $0.isCompleted }
            ),
        TaskReducer()
            .filterOffset(
                keyPath: \.tasks,
                prism: Action.highPriorityPrism,
                predicate: { $0.priority == .high }
            ),
    ]).reduce(oldState: oldState, with: action)
}
```

---

## 6. Dispatching from the View

```swift
// Complete all work tasks
store.dispatch(.completeByCategory("Work", .complete))

// Uncomplete all high-priority tasks
store.dispatch(.completeByPriority(.high, .uncomplete))

// Toggle all currently-completed tasks
store.dispatch(.toggleCompleted(.toggle))
```

---

## When NOT to Use `.filterOffset()`

| Situation | Better approach |
|-----------|-----------------|
| Targeting a single element by its ID | `.keyed(keyPath:prism:)` |
| Targeting a single element by its position | `.offset(keyPath:prism:)` |
| All elements always receive the action | Loop in the parent reducer directly |
| The batch selection needs middleware side effects | Handle the case in the parent reducer, loop manually, dispatch follow-up actions via middleware |
