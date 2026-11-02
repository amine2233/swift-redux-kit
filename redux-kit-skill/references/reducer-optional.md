---
name: reducer-optional
description: Guide to .optional() — wrapping a reducer or middleware to handle Optional<State>, making it a no-op when state is nil.
---

# `.optional()` — Optional-state Reducer & Middleware

`.optional()` wraps any reducer or middleware so that it operates on `Optional<FeatureState>` instead of `FeatureState`.
When the state is `nil` the reducer returns `nil` unchanged and the middleware returns `nil` (no follow-up action).
When the state is non-nil, the inner reducer or middleware runs normally.

Use `.optional()` when:

- A feature is only active part of the time (e.g., a selected item detail, an open modal's state).
- You want to keep the feature reducer pure and free of `Optional` handling.
- The parent state has an optional sub-state property: `var detail: DetailReducer.State?`.

---

## Anatomy

```
ParentState
  └── detail: DetailReducer.State?    ← optional property

ParentAction
  └── case detail(DetailAction)       ← same prism as .lifted()

DetailReducer operates on DetailReducer.State (non-optional)
.optional() makes it safe when detail == nil
```

---

## 1. Optional Reducer

Combine `.optional()` with `.lifted()` to scope to a nullable property.

```swift
struct AppReducer: Reducer {
    struct State: Hashable {
        var items: [Item] = []
        var detail: DetailReducer.State? = nil   // nil when nothing is selected
    }

    enum Action: Actionable {
        case selectItem(Item)
        case dismissDetail
        case detail(DetailReducer.Action)
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState

        switch action {
        case let .selectItem(item):
            state.detail = DetailReducer.State(item: item)

        case .dismissDetail:
            state.detail = nil

        case .detail:
            break   // handled by the lifted optional reducer below
        }

        // Apply the optional-lifted detail reducer for .detail(_) actions
        return DetailReducer()
            .optional()                                     // wraps for State?
            .lifted(keyPath: \.detail, prism: .detailPrism) // scopes to AppState
            .reduce(oldState: state, with: action)
    }
}

extension AppAction {
    static var detailPrism: Prism<AppAction, DetailReducer.Action> {
        .init(
            embed: AppAction.detail,
            extract: {
                guard case let .detail(a) = $0 else { return nil }
                return a
            }
        )
    }
}
```

Behaviour:

- When `state.detail == nil`, `.detail(_)` actions are silently ignored.
- When `state.detail != nil`, the inner `DetailReducer` handles the action.

---

## 2. Optional Middleware

```swift
actor DetailMiddleware: Middleware {
    func process(
        state: DetailReducer.State,
        with action: DetailReducer.Action
    ) async -> DetailReducer.Action? {
        switch action {
        case .load:
            let data = try? await api.fetchDetail(state.itemId)
            return .setData(data)
        default:
            return nil
        }
    }
}

// Wiring
let middlewares: [any Middleware<AppState, AppAction>] = [
    DetailMiddleware()
        .optional()
        .lifted(keyPath: \.detail, prism: AppAction.detailPrism),
]
```

When `detail == nil`, the middleware returns `nil` immediately without calling the inner `process`.
When `detail != nil`, the inner middleware receives the unwrapped state.

---

## 3. Standalone Optional Reducer (without .lifted())

When the parent reducer's own state is already `Optional`, use `.optional()` directly without `.lifted()`.

```swift
// Reducer that works on non-optional state
struct CounterReducer: Reducer {
    struct State: Hashable { var count: Int = 0 }
    enum Action: Actionable { case increment; case decrement }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .increment: state.count += 1
        case .decrement: state.count -= 1
        }
        return state
    }
}

// Safe use with optional state
let optionalReducer = CounterReducer().optional()
// State? — no-op when nil, delegates to CounterReducer when non-nil
```

---

## Key Differences from Manual Handling

| | Manual `if let` in parent reducer | `.optional()` |
|---|---|---|
| Feature reducer knows about `Optional` | No (parent handles it) | No (`.optional()` handles it) |
| Code location | Parent `reduce()` switch case | Wiring at store creation |
| Composability | Manual per-case | Works with `.lifted()`, `.keyed()`, `.offset()` |

---

## When NOT to Use `.optional()`

| Situation | Better approach |
|-----------|-----------------|
| State is always present (just starts empty) | Non-optional sub-state with a `.loaded` flag |
| Optional state has its own load/dismiss lifecycle that the parent must coordinate | Handle explicitly in the parent reducer's switch |
| Two or more optional states interact | Coordinate in the parent reducer directly |
