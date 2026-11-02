---
name: reducer-offset
description: Guide to .offset(keyPath:prism:) — scoping a reducer or middleware to a single Array element identified by its integer index.
---

# `.offset()` — Array-scoped Reducer & Middleware

`.offset(keyPath:prism:)` lifts a feature reducer (or middleware) so that it operates on **one element in a `[FeatureState]` array** inside the parent state, identified by its integer index.
The parent action carries both the index and the feature action; the prism extracts that pair.

Use `.offset()` when:

- The list is **ordered** and elements are identified by their position (e.g., steps in a wizard, slides in a deck, pages in a paginated flow).
- The feature reducer should be unaware of the surrounding array.
- Indices are stable for the lifetime of the dispatched action.

> **Prefer `.keyed()` over `.offset()` for ID-keyed lists** (e.g., `[Item]` where `Item` has a stable `id`). Index-based addressing breaks when items are reordered or deleted.

---

## Anatomy

```
ParentState
  └── [FeatureState]        ← keyPath points here

ParentAction
  └── case item(Int, FeatureAction)   ← prism extracts (Int, FeatureAction)

FeatureReducer operates on FeatureState with FeatureAction
```

---

## 1. Define the Prism

The prism target is a tuple `(Int, FeatureAction)`.

```swift
enum AppAction: Actionable {
    case step(index: Int, action: StepReducer.Action)
    // ...other cases
}

extension AppAction {
    static var stepPrism: Prism<AppAction, (Int, StepReducer.Action)> {
        .init(
            embed: { AppAction.step(index: $0.0, action: $0.1) },
            extract: {
                guard case let .step(index, action) = $0 else { return nil }
                return (index, action)
            }
        )
    }
}
```

---

## 2. Offset Reducer

```swift
struct WizardReducer: Reducer {
    struct State: Hashable {
        var steps: [StepReducer.State] = []
        var currentIndex: Int = 0
    }

    func reduce(oldState: State, with action: AppAction) -> State {
        CombinedReducer(reducers: [
            StepReducer()
                .offset(keyPath: \.steps, prism: AppAction.stepPrism),
        ]).reduce(oldState: oldState, with: action)
    }
}
```

When `AppAction.step(index: 2, action: .validate)` arrives:

1. The prism extracts `(2, .validate)`.
2. `StepReducer` is called with `steps[2]` as its state.
3. The result is written back to `steps[2]`.
4. If `2` is out of bounds, the action is a no-op.

---

## 3. Offset Middleware

```swift
actor StepMiddleware: Middleware {
    func process(
        state: StepReducer.State,
        with action: StepReducer.Action
    ) async -> StepReducer.Action? {
        switch action {
        case .validate:
            let isValid = await someAsyncValidation(state)
            return .setValid(isValid)
        default:
            return nil
        }
    }
}

// Wiring
let middlewares: [any Middleware<WizardReducer.State, AppAction>] = [
    StepMiddleware()
        .offset(keyPath: \.steps, prism: AppAction.stepPrism),
]
```

The returned action (if non-nil) is re-embedded as `AppAction.step(index: sameIndex, action: returnedAction)` and re-dispatched.

---

## 4. Dispatching from the View

```swift
// Dispatch an action targeting the step at index 2
store.dispatch(.step(index: 2, action: .validate))

// Dispatch for the currently active step
store.dispatch(.step(index: store.currentIndex, action: .next))
```

---

## 5. Initialising the Array

Populate the array before dispatching offset actions. Elements missing at a given index are silently ignored.

```swift
// In the parent reducer
case .load:
    state.steps = [
        StepReducer.State(title: "Personal Info"),
        StepReducer.State(title: "Address"),
        StepReducer.State(title: "Confirmation"),
    ]
```

---

## When NOT to Use `.offset()`

| Situation | Better approach |
|-----------|-----------------|
| Items have stable IDs and may be reordered | `.keyed()` with the item ID as key |
| The whole list is processed at once | Loop in the parent reducer directly |
| Only one element exists (optional detail) | `.optional()` on a non-array sub-state |
