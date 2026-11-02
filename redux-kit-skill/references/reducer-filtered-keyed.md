---
name: reducer-filtered-keyed
description: Guide to .filteredKeyed(keyPath:prism:predicate:) — applying a reducer action to all dictionary values that match a predicate, enabling batch operations on filtered subsets of keyed state.
---

# `.filteredKeyed()` — Predicate-filtered Batch Dictionary Reducer

`.filteredKeyed(keyPath:prism:predicate:)` lifts a feature reducer so it applies an action to **every value in a `[Key: State]` dictionary that satisfies a predicate**.
Unlike `.keyed()` which targets one specific entry by its key, `filteredKeyed` is a bulk operation — it touches zero, one, or many values in a single reduce call.

> **Reducer only** — there is no middleware equivalent of `.filteredKeyed()`.

---

## How It Differs from `.keyed()` and `.filterOffset()`

| | `.keyed()` | `.filteredKeyed()` | `.filterOffset()` |
|---|---|---|---|
| Storage | `[Key: State]` | `[Key: State]` | `[State]` |
| Target | One entry by **key** | All values matching a **predicate** | All elements matching a **predicate** |
| Prism target | `(Key, ChildAction)` | `ChildAction` (no key) | `ChildAction` (no index) |
| Entries modified | Exactly one (or zero if key absent) | Zero or more | Zero or more |
| Use case | Single-item interaction | Bulk on keyed state | Bulk on array state |

> **Prefer `.filteredKeyed()` over `.filterOffset()`** when state is stored as `[Key: State]` — dictionary access is O(1) vs array scan, and it avoids index fragility.

---

## Anatomy

```
ParentState
  └── rowStates: [Item.ID: RowReducer.State]   ← keyPath points here

ParentAction
  └── case bulkComplete(RowAction)              ← prism extracts RowAction (no key)

predicate: (RowReducer.State) -> Bool           ← decides which values receive the action

RowReducer operates on RowReducer.State with RowAction
```

---

## 1. Define the Element Reducer

The element reducer is unaware it will be used in a batch context.

```swift
struct RowReducer: Reducer {
    struct State: Hashable {
        var isSelected: Bool = false
        var isExpanded: Bool = false
        var isEditing: Bool = false
    }

    enum Action: Actionable {
        case select
        case deselect
        case collapse
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .select:   state.isSelected = true
        case .deselect: state.isSelected = false
        case .collapse: state.isExpanded = false
        }
        return state
    }
}
```

---

## 2. Define the Parent State & Action

Each bulk operation gets its own action case. The prism for `filteredKeyed` extracts only `ChildAction` — no key.

```swift
struct AppReducer: Reducer {
    struct State: Hashable {
        var items: [Item] = []
        var rowStates: [Item.ID: RowReducer.State] = [:]
    }

    enum Action: Actionable {
        case row(id: Item.ID, action: RowReducer.Action)   // single-item via .keyed()
        case deselectAll(RowReducer.Action)                // bulk via .filteredKeyed()
        case collapseExpanded(RowReducer.Action)           // bulk via .filteredKeyed()
    }
}
```

---

## 3. Static Prism (Fixed Filter)

Use a `static let` prism when the filter criterion is constant.

```swift
extension AppReducer.Action {
    static let deselectAllPrism = Prism<AppReducer.Action, RowReducer.Action>(
        embed: { AppReducer.Action.deselectAll($0) },
        extract: {
            guard case let .deselectAll(action) = $0 else { return nil }
            return action
        }
    )

    static let collapseExpandedPrism = Prism<AppReducer.Action, RowReducer.Action>(
        embed: { AppReducer.Action.collapseExpanded($0) },
        extract: {
            guard case let .collapseExpanded(action) = $0 else { return nil }
            return action
        }
    )
}
```

---

## 4. Parent Reducer — Use `.filteredKeyed()` for Bulk Actions

Handle single-item actions via `.keyed()` and bulk actions via `.filteredKeyed()`.

```swift
extension AppReducer {
    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState

        switch action {
        case let .loaded(items):
            state.items = items
            for item in items where state.rowStates[item.id] == nil {
                state.rowStates[item.id] = .init()
            }

        case .row:
            break   // handled by .keyed() below

        case .deselectAll:
            break   // handled by .filteredKeyed() below

        case .collapseExpanded:
            break   // handled by .filteredKeyed() below
        }

        return CombinedReducer(reducers: [
            // Single-item: target one entry by key
            RowReducer()
                .keyed(keyPath: \.rowStates, prism: Action.rowPrism),

            // Bulk: deselect all selected rows
            RowReducer()
                .filteredKeyed(
                    keyPath: \.rowStates,
                    prism: Action.deselectAllPrism,
                    predicate: { $0.isSelected }
                ),

            // Bulk: collapse all expanded rows
            RowReducer()
                .filteredKeyed(
                    keyPath: \.rowStates,
                    prism: Action.collapseExpandedPrism,
                    predicate: { $0.isExpanded }
                ),
        ]).reduce(oldState: state, with: action)
    }
}
```

`.filteredKeyed()` automatically:

1. Extracts `ChildAction` using the prism — returns unchanged state if prism yields `nil`.
2. Iterates every dictionary value and applies the predicate.
3. Calls the element reducer only for matching values.
4. Only writes back to the dictionary when at least one value actually changed.

---

## 5. Dynamic Prism (Parametric Filter)

Use a factory function when the criterion is carried inside the action.

```swift
enum AppAction: Actionable {
    case bulkCompleteByCategory(String, ItemAction)
}

extension AppAction {
    static func categoryPrism(for category: String) -> Prism<AppAction, ItemAction> {
        .init(
            embed: { AppAction.bulkCompleteByCategory(category, $0) },
            extract: {
                guard case let .bulkCompleteByCategory(cat, action) = $0, cat == category else {
                    return nil
                }
                return action
            }
        )
    }
}

// In the reducer:
case let .bulkCompleteByCategory(category, _):
    return ItemReducer()
        .filteredKeyed(
            keyPath: \.itemStates,
            prism: Action.categoryPrism(for: category),
            predicate: { $0.category == category }
        )
        .reduce(oldState: state, with: action)
```

---

## 6. Dispatching from the View

```swift
// Deselect all currently-selected rows
store.dispatch(.deselectAll(.deselect))

// Collapse all expanded rows
store.dispatch(.collapseExpanded(.collapse))

// Bulk complete all work items (dynamic filter)
store.dispatch(.bulkCompleteByCategory("Work", .complete))
```

---

## When NOT to Use `.filteredKeyed()`

| Situation | Better approach |
|-----------|-----------------|
| Targeting a single entry by its key | `.keyed(keyPath:prism:)` |
| State is stored as an array, not a dictionary | `.filterOffset(keyPath:prism:predicate:)` |
| All values always receive the action | Loop in the parent reducer directly |
| The batch selection needs middleware side effects | Handle in the parent reducer, loop manually, dispatch follow-up actions via middleware |
