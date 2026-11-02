---
name: testing-store
description: Guide to the ReduxKitTesting package — TestStore, ReducerProbe, and MiddlewareProbe sugar for asserting state transitions and middleware effects exhaustively.
---

# Testing with ReduxKitTesting

`ReduxKitTesting` is a separate library product that adds sugar syntax for testing ReduxKit features.
Prefer it over hand-rolled `Task { await store.send(...) }` patterns whenever you need to assert the
state after each action **and** the follow-up actions a middleware emits.

For plain reducer/middleware unit tests without the new package, see
[implementation-tests.md](implementation-tests.md). This guide covers the `ReduxKitTesting` helpers.

## Setup

Add the product to the test target and import it next to `ReduxKit`:

```swift
// Package.swift
.testTarget(
    name: "MyFeatureTests",
    dependencies: ["MyFeature", "ReduxKitTesting"]
)
```

```swift
import Testing
import ReduxKit
import ReduxKitTesting
```

It uses Swift Testing (`@Test`, `#expect`). Failures are reported via `Issue.record(_:sourceLocation:)`
and point at the failing line. Mark suites that build a `TestStore` with `@MainActor`.

## The three helpers

| Helper | Layer | Sync/async |
|--------|-------|------------|
| `TestStore` | Reducer + middleware together (integration) | async, `@MainActor` |
| `ReducerProbe` | Reducer in isolation | synchronous |
| `MiddlewareProbe` | Middleware in isolation | async |

---

## 1. `TestStore` — full integration with exhaustive assertions

`TestStore` wraps your reducer to record every transition, then lets you walk them:

- `send(_:_:)` — dispatch an action; the trailing closure mutates a copy of the current state to
  describe what you expect **after reducing only that action**.
- `receive(_:_:)` — assert the next action a middleware emitted (depth-first dispatch order) and its state.
- `finish()` — fail if any emitted action was never received.

```swift
@MainActor
struct SearchStoreTests {
    let repo = Repo(id: 1, name: "swift", description: nil)

    func makeStore(repos: [Repo] = []) -> TestStore<SearchReducer.State, SearchReducer.Action> {
        TestStore(
            initialState: .init(),
            reducer: SearchReducer(),
            middlewares: [
                SearchMiddleware(dependencies: .init { _ in SearchResponse(items: repos) })
            ]
        )
    }

    @Test
    func searchUpdatesRepos() async {
        let store = makeStore(repos: [repo])

        // `.search` sets isLoading synchronously in the reducer.
        await store.send(.search(query: "swift")) { $0.isLoading = true }

        // The middleware fetched results and dispatched `.setResults`.
        await store.receive(.setResults(repos: [repo])) {
            $0.isLoading = false
            $0.repos = [repo]
        }

        store.finish()
    }
}
```

### Key rules

- `send`'s closure asserts only the change made by the **sent** action. Middleware follow-ups belong to
  `receive`, in the order they were dispatched.
- Omit the closure when an action does not change state on its own: `await store.send(.sideEffect)`.
- **Exhaustivity is on by default.** Every reduced action must be received, or `finish()` fails — this
  is how you catch unexpected effects. Exhaustivity is keyed on reducer invocations, not state changes:
  a follow-up whose reducer produces identical state still must be received.
- For tests that only care about the final state, set `store.exhaustivity = .disabled`. Then each `send`
  asserts its immediate transition and silently drains the rest of the cascade; read `store.state`.
- Use the no-middleware convenience init when there is nothing to intercept:
  `TestStore(initialState: .init(), reducer: SearchReducer())`.

### Timing

`receive` never waits or times out — the cascade already completed inside `send`. Middleware that
performs real delays (`Task.sleep`) blocks `send` for that wall-clock time; inject a clock/dependency
stub so tests stay fast (never use `.production` dependencies).

---

## 2. `ReducerProbe` — synchronous reducer tests

A fluent given/when/then chain over a pure reducer. `send` reduces and advances state; `expect`
asserts. Both `expect` overloads (`expect(_ expected:)` for `Equatable` state, and
`expect { ... }` for custom assertions) return the probe for chaining.

```swift
@Test
func reducerChain() {
    SearchReducer().probe(SearchReducer.State())
        .send(.search(query: "swift"))
        .expect { #expect($0.isLoading == true) }
        .send(.setResults(repos: [repo]))
        .expect { #expect($0.isLoading == false && $0.repos == [repo]) }
}
```

One-liner for a single reduction (requires `Equatable` state):

```swift
expectReduce(
    CounterReducer(),
    from: State(counter: 0),
    action: .increment,
    to: State(counter: 1)
)
```

---

## 3. `MiddlewareProbe` — async middleware tests

Assert which action a middleware emits for a given state and input action. Inject a stub
`Dependencies` so tests never hit the network.

### Middleware under test

```swift
struct SearchMiddleware: Middleware {
    let dependencies: Dependencies

    func process(state: SearchReducer.State, with action: SearchReducer.Action) async -> SearchReducer.Action? {
        switch action {
        case let .search(query):
            // Swallow errors with `try?` and fall back to an empty list.
            let response = try? await dependencies.search(query)
            return .setResults(repos: response?.items ?? [])
        case .setResults:
            return nil   // already-handled action — stop the chain
        }
    }
}
```

### Probing every path

Build a fresh middleware per scenario with the matching stub, then assert the emission:

```swift
@MainActor
struct SearchMiddlewareTests {
    let repo = Repo(id: 42, name: "redux-kit", description: nil)

    func makeMiddleware(result: [Repo] = [], throwing: Bool = false) -> SearchMiddleware {
        SearchMiddleware(dependencies: .init { _ in
            if throwing { throw URLError(.badServerResponse) }
            return SearchResponse(items: result)
        })
    }

    @Test
    func searchEmitsResults() async {
        await makeMiddleware(result: [repo]).probe(state: SearchReducer.State())
            .expect(on: .search(query: "redux"), emits: .setResults(repos: [repo]))
    }

    @Test
    func searchFailureEmitsEmptyResults() async {
        // The middleware swallows the thrown error and still emits `.setResults`.
        await makeMiddleware(throwing: true).probe(state: SearchReducer.State())
            .expect(on: .search(query: "redux"), emits: .setResults(repos: []))
    }

    @Test
    func handledActionEmitsNothing() async {
        await makeMiddleware(result: [repo]).probe(state: SearchReducer.State())
            .expectNoAction(on: .setResults(repos: [repo]))
    }
}
```

Key points:

- `expect(on:emits:)` takes the emitted action (or `nil`); `expectNoAction(on:)` is shorthand for
  `emits: nil`.
- Assertions chain — `probe(state:)` returns the probe and so does each `expect`, so you can cover
  several inputs against the same state in one expression.
- Test the failure path by making the stub throw, and verify that actions the middleware does not
  handle emit nothing (return `nil`, which stops the dispatch chain).
- Never use `.production` dependencies — always inject a stub.

---

## When to use which

- Reducer logic only → `ReducerProbe` or `expectReduce`.
- Middleware side-effect mapping only → `MiddlewareProbe`.
- Full feature behaviour, including the order and state of middleware-emitted actions → `TestStore`.
