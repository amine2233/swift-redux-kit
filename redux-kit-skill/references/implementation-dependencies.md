---
name: implementation-dependencies
description: Guide to managing dependencies in a ReduxKit feature, including best practices for structuring the `Dependencies` type, creating stubs for testing and previews, and rules for when to use each dependency configuration.
---

# Dependencies — Mock, Preview, and Test

The `Dependencies` struct inside each middleware is the single seam for injecting different behaviours without changing any production code.

## The Pattern

```swift
actor SearchMiddleware: Middleware {
    struct Dependencies {
        var search: (String) async throws -> SearchResponse

        // Real network implementation — used in production
        static var production: Dependencies {
            .init { query in
                var components = URLComponents(string: "https://api.github.com/search/repositories")!
                components.queryItems = [.init(name: "q", value: query)]
                let (data, _) = try await URLSession.shared.data(from: components.url!)
                return try JSONDecoder().decode(SearchResponse.self, from: data)
            }
        }
    }

    let dependencies: Dependencies
    init(dependencies: Dependencies) { self.dependencies = dependencies }
}
```

`production` is the only place that touches the network, file system, pasteboard, or any other real system. Everything else is a closure swap.

---

## Static Stubs

Add named static stubs on `Dependencies` alongside `production`. Each stub is just an alternative initializer — no subclassing, no protocols.

```swift
extension SearchMiddleware.Dependencies {
    // Returns a fixed list — used in SwiftUI previews
    static var preview: Self {
        .init { _ in
            SearchResponse(items: [
                Repo(id: 1, name: "redux-kit", description: "Redux for Swift"),
                Repo(id: 2, name: "swift-ui-kit", description: "UI components"),
            ])
        }
    }

    // Simulates a loading state that never resolves — used to preview skeletons
    static var loading: Self {
        .init { _ in
            try await Task.sleep(for: .seconds(600))
            return SearchResponse(items: [])
        }
    }

    // Always throws — used to preview error states
    static var failing: Self {
        .init { _ in throw URLError(.notConnectedToInternet) }
    }

    // Returns empty results immediately
    static var empty: Self {
        .init { _ in SearchResponse(items: []) }
    }
}
```

---

## SwiftUI Previews

Use named stubs to preview every UI state in isolation — no network needed, no waiting.

```swift
// Happy path — shows a populated list
#Preview("Results") {
    NavigationStack {
        SearchView(
            store: SearchStore(
                initialState: .init(),
                reducer: SearchReducer(),
                middlewares: [SearchMiddleware(dependencies: .preview)]
            )
        )
    }
}

// Loading state — shows the redacted skeleton
#Preview("Loading") {
    NavigationStack {
        SearchView(
            store: SearchStore(
                initialState: SearchReducer.State(isLoading: true),
                reducer: SearchReducer(),
                middlewares: [SearchMiddleware(dependencies: .loading)]
            )
        )
    }
}

// Empty state
#Preview("Empty") {
    NavigationStack {
        SearchView(
            store: SearchStore(
                initialState: .init(),
                reducer: SearchReducer(),
                middlewares: [SearchMiddleware(dependencies: .empty)]
            )
        )
    }
}
```

When the view creates its own store (`@State private var store = …`), override it in the `init` parameter instead:

```swift
struct SearchView: View {
    @State private var store: SearchStore

    init(store: SearchStore = SearchStore(
        initialState: .init(),
        reducer: SearchReducer(),
        middlewares: [SearchMiddleware(dependencies: .production)]
    )) {
        self.store = store
    }
}

// Preview then passes its own stub store
#Preview { SearchView(store: SearchStore(…dependencies: .preview…)) }
```

---

## Unit Tests

Build an inline stub directly in the test — no need for a named static unless it is reused.

### Middleware tests

```swift
@MainActor
struct SearchMiddlewareTests {
    let repo = Repo(id: 1, name: "redux-kit", description: nil)

    // Inline stub — success path
    @Test
    func returnsResults() async {
        let middleware = SearchMiddleware(dependencies: .init { _ in
            SearchResponse(items: [self.repo])
        })
        let action = await middleware.process(
            state: .init(),
            with: .search(query: "redux")
        )
        #expect(action == .setResults(repos: [repo]))
    }

    // Inline stub — failure path
    @Test
    func failureReturnsEmpty() async {
        let middleware = SearchMiddleware(dependencies: .init { _ in
            throw URLError(.badServerResponse)
        })
        let action = await middleware.process(
            state: .init(),
            with: .search(query: "redux")
        )
        #expect(action == .setResults(repos: []))
    }
}
```

### Store integration tests

```swift
@MainActor
struct SearchStoreTests {
    let repo = Repo(id: 1, name: "swift", description: nil)

    func makeStore(
        initialState: SearchReducer.State = .init(),
        dependencies: SearchMiddleware.Dependencies
    ) -> SearchStore {
        SearchStore(
            initialState: initialState,
            reducer: SearchReducer(),
            middlewares: [SearchMiddleware(dependencies: dependencies)]
        )
    }

    @Test
    func searchUpdatesRepos() async {
        let store = makeStore(dependencies: .init { _ in SearchResponse(items: [repo]) })
        await store.send(.search(query: "swift"))
        #expect(store.repos == [repo])
        #expect(store.isLoading == false)
    }

    @Test
    func cancellationPreservesState() async {
        let existing = [Repo(id: 0, name: "existing", description: nil)]
        let store = makeStore(
            initialState: .init(repos: existing),
            dependencies: .init { _ in
                try await Task.sleep(for: .seconds(1))
                return SearchResponse(items: [self.repo])
            }
        )
        let task = Task { await store.send(.search(query: "swift")) }
        try? await Task.sleep(for: .milliseconds(10))
        task.cancel()
        await task.value
        #expect(store.repos == existing)
    }
}
```

---

## Rules

| Context | Dependency to use |
|---------|-------------------|
| Production app | `.production` |
| SwiftUI `#Preview` (data) | `.preview` (named stub) |
| SwiftUI `#Preview` (loading) | `.loading` (named stub) |
| SwiftUI `#Preview` (error) | `.failing` (named stub) |
| Unit / integration test | inline `.init { … }` |

- **Never** use `.production` in tests or previews — it causes network calls and flaky tests.
- **Never** use `XCTest` or create mock classes — inline closure stubs are sufficient.
- Add a named stub only when the same fixture is needed in more than one place.
