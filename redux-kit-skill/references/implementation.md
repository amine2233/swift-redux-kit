---
name: implementation
description: Guide to implementing a complete ReduxKit feature, including State, Action, Reducer, Middleware, Store, and SwiftUI integration.
---

# Implementation Guide

A complete ReduxKit feature is composed of four parts: **State**, **Action**, **Reducer**, and **Middleware**.
The example below is a GitHub repository search feature.

## 1. Reducer

Implement `Reducer` to produce a new state from the old one and an action.
The reducer must be **pure** and **synchronous** — no side effects here.

```swift
struct SearchReducer: Reducer {

    enum Action: Actionable {
        case search(query: String)
        case setResults(repos: [Repo])
    }

    struct State: Equatable {
        var repos: [Repo] = []
        var isLoading = false
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState

        switch action {
        case .search:
            state.isLoading = true
        case let .setResults(repos):
            state.repos = repos
            state.isLoading = false
        }

        return state
    }
}
```

## 2. State

The state should be defined as an `Equatable` struct holding all the data the UI needs.

## 3. Action

The acton can be an `enum` conforming to `Actionable`. Each case represents a discrete event or intent.

## 4. Middleware

Implement `Middleware` (marked `actor` for thread safety) to handle side effects such as network requests.
Return an `Action?` to dispatch a follow-up action, or `nil` to stop the chain.

```swift
actor SearchMiddleware: Middleware {
    struct Dependencies {
        var search: (String) async throws -> SearchResponse

        static var production: Dependencies {
            .init { query in
                guard var urlComponents = URLComponents(string: "https://api.github.com/search/repositories")
                else { return .init(items: []) }
                urlComponents.queryItems = [.init(name: "q", value: query)]
                guard let url = urlComponents.url else { return .init(items: []) }
                let (data, _) = try await URLSession.shared.data(from: url)
                return try JSONDecoder().decode(SearchResponse.self, from: data)
            }
        }
    }

    let dependencies: Dependencies
    init(dependencies: Dependencies) { self.dependencies = dependencies }

    func process(state: State, with action: Action) async -> Action? {
        switch action {
        case let .search(query):
            let results = try? await dependencies.search(query)
            guard !Task.isCancelled else {
                return .setResults(repos: state.repos)
            }
            return .setResults(repos: results?.items ?? [])
        default:
            return nil
        }
    }
}
```

> **Dependency injection via a `Dependencies` struct** keeps the middleware testable: swap `production` for a mock in tests.

> **Cancellation check**: always guard with `Task.isCancelled` after an `await` to avoid delivering stale results.

## 5. Store

Wire everything together with a `typealias` and instantiate inside the view.

```swift
typealias SearchStore = Store<SearchReducer.State, SearchReducer.Action>
```

## 6. SwiftUI View

Create the store as `@State` so it lives for the lifetime of the view. Access state directly on `store`, and dispatch actions via `store.send(_:)`.

```swift
@MainActor
struct SearchView: View {
    @State private var store = SearchStore(
        initialState: .init(),
        reducer: SearchReducer(),
        middlewares: [SearchMiddleware(dependencies: .production)]
    )
    @State private var query = ""

    var body: some View {
        List(store.repos) { repo in
            VStack(alignment: .leading) {
                Text(repo.name).font(.headline)
                if let description = repo.description {
                    Text(description)
                }
            }
        }
        .redacted(reason: store.isLoading ? .placeholder : [])
        .searchable(text: $query)
        .task(id: query) {
            await store.send(.search(query: query))
        }
        .navigationTitle("Github Search")
    }
}
```

Key points:

- `@State private var store` — store is owned by the view and observed automatically via `@Observable`.
- `.task(id: query)` — automatically cancels and restarts the task whenever `query` changes, enabling debounce-free cancellation.
- `.redacted(reason:)` — drives loading UI directly from `store.isLoading` with no extra state.

## 7. App Entry Point

```swift
@main
struct GithubApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SearchView()
            }
        }
    }
}
```

## 8. Send actions

To send or dispatch an action, call:

### `await store.send(.actionCase(parameters))`

Use await when you need to send an action inside an async context, such as a `.task` modifier or an `async` function.
This allows you to wait for any asynchronous processing in the middleware to complete before proceeding.

### `store.dispatch(.actionCase(parameters))`

Use dispatch when you want to send an action without awaiting its completion.
This is useful for fire-and-forget actions or when you don't need to wait for the result of the middleware processing.

You should use it on Button actions or any synchronous context where awaiting is not necessary or available.
