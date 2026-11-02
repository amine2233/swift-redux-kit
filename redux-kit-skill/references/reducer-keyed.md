---
name: reducer-keyed
description: Guide to .keyed(keyPath:prism:) — scoping a reducer or middleware to a single Dictionary entry identified by a key.
---

# `.keyed()` — Dictionary-scoped Reducer & Middleware

`.keyed(keyPath:prism:)` lifts a feature reducer (or middleware) so that it operates on **one entry in a `[Key: FeatureState]` dictionary** inside the parent state.
The parent action carries both the key and the feature action; the prism extracts that pair.

Use `.keyed()` when:

- Each dictionary entry is an independent stateful entity (e.g., per-item editing state, per-channel unread count).
- The feature reducer should be unaware of the surrounding dictionary.
- The same `FeatureReducer` handles all entries — only the key differs.

---

## Anatomy

```
ParentState
  └── [Key: FeatureState]   ← keyPath points here

ParentAction
  └── case feature(Key, FeatureAction)   ← prism extracts (Key, FeatureAction)

FeatureReducer operates on FeatureState with FeatureAction
```

---

## 1. Define the Prism

The prism target is a tuple `(Key, FeatureAction)`.

```swift
enum AppAction: Actionable {
    case row(id: Item.ID, action: ItemRowReducer.Action)
    // ...other cases
}

extension AppAction {
    static var rowPrism: Prism<AppAction, (Item.ID, ItemRowReducer.Action)> {
        .init(
            embed: { AppAction.row(id: $0.0, action: $0.1) },
            extract: {
                guard case let .row(id, action) = $0 else { return nil }
                return (id, action)
            }
        )
    }
}
```

---

## 2. Keyed Reducer

```swift
struct AppReducer: Reducer {
    struct State: Hashable {
        var items: [Item] = []
        var rowStates: [Item.ID: ItemRowReducer.State] = [:]
    }

    func reduce(oldState: State, with action: AppAction) -> State {
        CombinedReducer(reducers: [
            ItemRowReducer()
                .keyed(keyPath: \.rowStates, prism: AppAction.rowPrism),
        ]).reduce(oldState: oldState, with: action)
    }
}
```

When `AppAction.row(id: someID, action: .toggleExpanded)` arrives:

1. The prism extracts `(someID, .toggleExpanded)`.
2. `ItemRowReducer` is called with `rowStates[someID]` as its state.
3. The result is written back to `rowStates[someID]`.
4. If `someID` is not in the dictionary, the action is a no-op.

---

## 3. Seeding Missing Entries

`.keyed()` will silently skip actions for keys that are absent from the dictionary.
Seed initial values when the parent loads data:

```swift
case let .loaded(items):
    state.items = items
    for item in items where state.rowStates[item.id] == nil {
        state.rowStates[item.id] = .init()
    }
```

---

## 4. Keyed Middleware

The middleware is lifted with the same prism. It receives the feature state (one entry) and feature action, and returns a feature action (or `nil`).

```swift
actor ItemRowMiddleware: Middleware {
    func process(
        state: ItemRowReducer.State,
        with action: ItemRowReducer.Action
    ) async -> ItemRowReducer.Action? {
        switch action {
        case .toggleExpanded:
            // analytics, persistence, etc.
            return nil
        default:
            return nil
        }
    }
}

// Wiring
let middlewares: [any Middleware<AppState, AppAction>] = [
    ItemRowMiddleware()
        .keyed(keyPath: \.rowStates, prism: AppAction.rowPrism),
]
```

The returned action (if non-nil) is re-embedded as `AppAction.row(id: sameID, action: returnedAction)` and re-dispatched.

---

## 5. Dispatching from the View

```swift
store.dispatch(.row(id: item.id, action: .toggleExpanded))
```

The parent store routes the action through the keyed reducer and middleware automatically.

---

## When NOT to Use `.keyed()`

| Situation | Better approach |
|-----------|-----------------|
| Row state is ephemeral UI (expand/collapse that can reset on reload) | `@State` inside the row view |
| Dictionary has a single well-known key | `.lifted(keyPath:prism:)` to a non-optional sub-state |
| Parent reducer needs to coordinate across multiple entries | Handle the case directly in the parent reducer |
