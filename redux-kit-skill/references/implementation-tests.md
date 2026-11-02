---
name: implementation-tests
description: Guide to testing a ReduxKit feature, covering Reducer, Middleware, and Store (integration) tests with Swift Testing.
---

# Test Implementation Guide

Tests for a ReduxKit feature cover three independent layers: **Reducer**, **Middleware**, and **Store** (integration).
The examples below map directly to the `SearchReducer.State / SearchReducer.Action / SearchReducer / SearchMiddleware`
types from the ExampleApp.

Each layer is tested in separate files.

## Setup

```swift
import Testing
@testable import ReduxKit
```

Use Swift Testing (`@Test`, `#expect`) — this is the testing framework used across the project.

---

## 1. Testing the Reducer

Reducers are pure functions, so tests are synchronous and need no store.

```swift
@MainActor
struct SearchReducerTests {
    let reducer = SearchReducer()

    @Test
    func searchSetsLoading() {
        let state = reducer.reduce(
            oldState: SearchReducer.State(),
            with: .search(query: "swift")
        )
        #expect(state.isLoading == true)
        #expect(state.repos.isEmpty)
    }

    @Test
    func setResultsClearsLoading() {
        let repos = [Repo(id: 1, name: "swift", description: nil)]
        let state = reducer.reduce(
            oldState: SearchReducer.State(repos: [], isLoading: true),
            with: .setResults(repos: repos)
        )
        #expect(state.isLoading == false)
        #expect(state.repos == repos)
    }
}
```

Key points:

- Call `reduce(oldState:with:)` directly — no store needed.
- Assert only on the properties changed by that action.

---

## 2. Testing the Middleware

Inject a controlled `Dependencies` stub so tests never hit the network.

```swift
@MainActor
struct SearchMiddlewareTests {
    let repo = Repo(id: 42, name: "redux-kit", description: "Redux for Swift")

    func makeMiddleware(
        result: [Repo] = [],
        throwing: Bool = false
    ) -> SearchMiddleware {
        SearchMiddleware(dependencies: .init {
            if throwing { throw URLError(.badServerResponse) }
            return SearchResponse(items: result)
        })
    }

    @Test
    func searchReturnsResults() async {
        let middleware = makeMiddleware(result: [repo])
        let action = await middleware.process(
            state: SearchReducer.State(),
            with: .search(query: "redux")
        )
        #expect(action == .setResults(repos: [repo]))
    }

    @Test
    func searchFailureReturnsEmptyResults() async {
        let middleware = makeMiddleware(throwing: true)
        let action = await middleware.process(
            state: SearchReducer.State(),
            with: .search(query: "redux")
        )
        #expect(action == .setResults(repos: []))
    }

    @Test
    func setResultsActionIsIgnored() async {
        let middleware = makeMiddleware(result: [repo])
        let action = await middleware.process(
            state: SearchReducer.State(),
            with: .setResults(repos: [repo])
        )
        #expect(action == nil)
    }
}
```

Key points:

- Use a `Dependencies` stub, never `Dependencies.production`.
- Test the failure path by having the stub throw — the middleware swallows errors with `try?` and returns an empty list.
- Verify that unhandled actions return `nil` (stop the chain).

---

## 3. Testing the Store (Integration)

Integration tests exercise the full dispatch cycle: reducer + middleware together.

```swift
@MainActor
struct SearchStoreTests {
    let repo = Repo(id: 1, name: "swift", description: nil)

    func makeStore(repos: [Repo] = []) -> SearchStore {
        SearchStore(
            initialState: .init(),
            reducer: SearchReducer(),
            middlewares: [
                SearchMiddleware(dependencies: .init { _ in
                    SearchResponse(items: repos)
                })
            ]
        )
    }

    @Test
    func searchUpdatesRepos() async {
        let store = makeStore(repos: [repo])

        await store.send(.search(query: "swift"))

        #expect(store.isLoading == false)
        #expect(store.repos == [repo])
    }

    @Test
    func loadingIsTrueBeforeMiddlewareCompletes() async {
        // Middleware with a delay — check state between dispatch and completion
        let store = SearchStore(
            initialState: .init(),
            reducer: SearchReducer(),
            middlewares: [
                SearchMiddleware(dependencies: .init { _ in
                    try await Task.sleep(nanoseconds: 500_000_000)
                    return SearchResponse(items: [self.repo])
                })
            ]
        )

        let task = Task { await store.send(.search(query: "swift")) }
        // Reducer runs synchronously, so isLoading is already true
        #expect(store.isLoading == true)
        await task.value
        #expect(store.isLoading == false)
    }

    @Test
    func cancellationPreservesExistingRepos() async {
        let existing = [Repo(id: 0, name: "existing", description: nil)]
        let store = SearchStore(
            initialState: SearchReducer.State(repos: existing, isLoading: false),
            reducer: SearchReducer(),
            middlewares: [
                SearchMiddleware(dependencies: .init { _ in
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    return SearchResponse(items: [self.repo])
                })
            ]
        )

        let task = Task { await store.send(.search(query: "swift")) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        await task.value

        // Cancelled middleware returns .setResults(repos: state.repos) — repos unchanged
        #expect(store.repos == existing)
    }
}
```

Key points:

- The reducer runs **synchronously** inside `send()`, so you can assert on `isLoading == true` immediately after launching an async task
  without awaiting it.
- To test cancellation, cancel the `Task` wrapping `send()` and await its completion before asserting.
- Always construct the store with a stub middleware — never use `.production` dependencies in tests.
