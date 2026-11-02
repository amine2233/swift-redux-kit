---
name: prism
description: Guide to Prism — the embed/extract type used to scope reducers and middlewares to sub-actions via .lifted(), .keyed(), and .offset().
---

# Prism

`Prism<Source, Target>` is a two-sided lens on an enum. Given a `Source` action type and a `Target` sub-action type it knows how to:

- **embed** — wrap a `Target` into a `Source` (always succeeds)
- **extract** — unwrap a `Source` to get a `Target?` (returns `nil` if the `Source` case doesn't match)

`Prism` is the glue that lets `.lifted()`, `.keyed()`, and `.offset()` scope a feature reducer or middleware to its own action type without any knowledge of the parent action.

---

## Defining a Prism

The canonical pattern is a static computed property on the **parent** action enum.

```swift
enum AppAction: Actionable {
    case search(SearchAction)
    case settings(SettingsAction)
}

extension AppAction {
    static var searchPrism: Prism<AppAction, SearchAction> {
        .init(
            embed: AppAction.search,          // SearchAction → AppAction
            extract: {
                guard case let .search(a) = $0 else { return nil }
                return a
            }
        )
    }

    static var settingsPrism: Prism<AppAction, SettingsAction> {
        .init(
            embed: AppAction.settings,
            extract: {
                guard case let .settings(a) = $0 else { return nil }
                return a
            }
        )
    }
}
```

> Keep prism definitions on the parent enum, not on the feature reducer or middleware. Feature code must stay ignorant of the parent.

---

## Using Prism with `.lifted(keyPath:prism:)` on a Reducer

`.lifted()` wraps a feature reducer so that it operates on a property of the parent state and only fires for matching parent actions.

```swift
// Feature — knows nothing about AppState / AppAction
struct SearchReducer: Reducer {
    struct State: Hashable { var query = ""; var results: [Repo] = [] }
    enum Action: Actionable { case setQuery(String); case setResults([Repo]) }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case let .setQuery(q):   state.query = q
        case let .setResults(r): state.results = r
        }
        return state
    }
}

// App — composes feature reducers
struct AppReducer: Reducer {
    struct State: Hashable {
        var search: SearchReducer.State = .init()
        var settings: SettingsReducer.State = .init()
    }

    func reduce(oldState: State, with action: AppAction) -> State {
        CombinedReducer(reducers: [
            SearchReducer()
                .lifted(keyPath: \.search, prism: AppAction.searchPrism),
            SettingsReducer()
                .lifted(keyPath: \.settings, prism: AppAction.settingsPrism),
        ]).reduce(oldState: oldState, with: action)
    }
}
```

When an `AppAction.search(…)` arrives:

1. The prism extracts the `SearchAction`.
2. `SearchReducer` reduces only `AppState.search`.
3. For any other `AppAction`, the lifted reducer is a no-op.

---

## Using Prism with `.lifted(keyPath:prism:)` on a Middleware

Identical pattern. The middleware returns a feature-level action; the lifted wrapper re-embeds it into the parent action before dispatching.

```swift
let middlewares: [any Middleware<AppState, AppAction>] = [
    SearchMiddleware(dependencies: .production)
        .lifted(keyPath: \.search, prism: AppAction.searchPrism),
    SettingsMiddleware(dependencies: .production)
        .lifted(keyPath: \.settings, prism: AppAction.settingsPrism),
]
```

The middleware only sees `SearchReducer.State` and `SearchReducer.Action`. The lifted wrapper handles translation to/from `AppAction`.

---

## Prism in .keyed() and .offset()

Both `.keyed()` and `.offset()` also require a `Prism`, but the `Target` is a tuple:

| Composition | Prism target |
|-------------|--------------|
| `.lifted()` | `ChildAction` |
| `.keyed()`  | `(Key, ChildAction)` |
| `.offset()` | `(Int, ChildAction)` |

See [reducer-keyed.md](reducer-keyed.md) and [reducer-offset.md](reducer-offset.md) for full examples.

---

## Rules

1. **Define prisms on the parent action** — keeps feature reducers and middlewares free of parent imports.
2. **The `embed` closure is just the enum case** — `AppAction.search` is already `(SearchAction) -> AppAction`, pass it directly.
3. **The `extract` closure is a guard-case pattern** — always return `nil` for non-matching cases.
4. **Prisms are value types** — they capture no state; define them as `static var` for zero allocation cost.
