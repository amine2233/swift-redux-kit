---
name: unidirectional-flow
description: Explain the three rules of unidirectional data flow in ReduxKit and how they work together to create a predictable architecture
---

# Unidirectional Data Flow

## The Three Rules

1. **One store per app** — a single `Store<AppState, AppAction>` owns all application state and is the only place actions are dispatched.
2. **One reducer per feature** — each feature owns its `State` and `Action` types and a reducer that knows nothing about the rest of the app. Feature reducers are composed into the app reducer via `.lifted(keyPath:prism:)`.
3. **The store lives in the SwiftUI Environment** — the app creates the store once at the root and injects it with `Provider`. Features read it from `@Environment`.

---

## Rule 1 — One App Store

```swift
// AppState.swift
struct AppState: Equatable {
    var search: SearchState = .init()
    var settings: SettingsState = .init()
}

// AppAction.swift
enum AppAction: Actionable {
    case search(SearchAction)
    case settings(SettingsAction)
}

// AppStore.swift
typealias AppStore = Store<AppState, AppAction>
```

The app store is the **single source of truth**. No feature ever creates its own independent store.

---

## Rule 2 — Feature Reducers Lifted into the App Reducer

Each feature defines its own reducer in isolation. It has **no knowledge of `AppState` or `AppAction`**.

```swift
// SearchReducer.swift  (feature — knows only SearchState / SearchAction)
struct SearchReducer: Reducer {
    func reduce(oldState: SearchState, with action: SearchAction) -> SearchState {
        var state = oldState
        switch action {
        case .search: state.isLoading = true
        case let .setResults(repos):
            state.repos = repos
            state.isLoading = false
        }
        return state
    }
}
```

The app reducer composes all feature reducers using `CombinedReducer` + `.lifted(keyPath:prism:)`. Each feature reducer is hidden behind a `Prism` that extracts its sub-action from `AppAction`.

```swift
// AppReducer.swift
extension AppAction {
    // Prism lets the lifted reducer extract SearchAction from AppAction
    static var searchPrism: Prism<AppAction, SearchAction> {
        .init(embed: AppAction.search) {
            guard case let .search(action) = $0 else { return nil }
            return action
        }
    }

    static var settingsPrism: Prism<AppAction, SettingsAction> {
        .init(embed: AppAction.settings) {
            guard case let .settings(action) = $0 else { return nil }
            return action
        }
    }
}

struct AppReducer: Reducer {
    func reduce(oldState: AppState, with action: AppAction) -> AppState {
        CombinedReducer(reducers: [
            SearchReducer().lifted(keyPath: \.search, prism: AppAction.searchPrism),
            SettingsReducer().lifted(keyPath: \.settings, prism: AppAction.settingsPrism),
        ]).reduce(oldState: oldState, with: action)
    }
}
```

The same `.lifted(keyPath:prism:)` pattern applies to middlewares:

```swift
let middlewares: [any Middleware<AppState, AppAction>] = [
    SearchMiddleware(dependencies: .production)
        .lifted(keyPath: \.search, prism: AppAction.searchPrism),
]
```

> **Why lift?** Feature reducers and middlewares remain independently testable because they only see their own `State` and `Action`. The app reducer is the only place that knows the full shape of the app.

---

## Rule 3 — Store via SwiftUI Environment

### Declare the environment key

```swift
// AppStore+Environment.swift
import SwiftUI

extension EnvironmentValues {
    @Entry var store: AppStore = AppStore(
        initialState: .init(),
        reducer: AppReducer(),
        middlewares: []
    )
}
```

### Inject at the root with `Provider`

`Provider` is the `ReduxKitUI` component that calls `.environment(_:_:)` for you.

```swift
// GithubApp.swift
import ReduxKitUI

@main
struct GithubApp: App {
    private let store = AppStore(
        initialState: .init(),
        reducer: AppReducer(),
        middlewares: [
            SearchMiddleware(dependencies: .production)
                .lifted(keyPath: \.search, prism: AppAction.searchPrism),
        ]
    )

    var body: some Scene {
        WindowGroup {
            Provider(\.store, store) {
                NavigationStack {
                    SearchView()
                }
            }
        }
    }
}
```

### Read from any feature view

```swift
// SearchView.swift
@MainActor
struct SearchView: View {
    @Environment(\.store) private var store
    @State private var query = ""

    var body: some View {
        List(store.search.repos) { repo in
            Text(repo.name)
        }
        .redacted(reason: store.search.isLoading ? .placeholder : [])
        .searchable(text: $query)
        .task(id: query) {
            await store.send(.search(.search(query: query)))
        }
    }
}
```

Feature views access only the slice of state they need via key paths (`store.search.repos`) and namespace their actions (`store.send(.search(…))`).

---

## Data Flow Diagram

```
User interaction
      │
      ▼
store.send(.search(.search(query:)))
      │
      ▼ synchronous
AppReducer → SearchReducer.lifted → SearchState.isLoading = true
      │
      ▼ async
SearchMiddleware.lifted → network call → .search(.setResults(repos:))
      │
      ▼ synchronous
AppReducer → SearchReducer.lifted → SearchState updated
      │
      ▼
SwiftUI re-renders SearchView
```

Actions always flow **in** to the store. State always flows **out** to views. Side effects (middleware) only ever produce new actions — they never touch state directly.
