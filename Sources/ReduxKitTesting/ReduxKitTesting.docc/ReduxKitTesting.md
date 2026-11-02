# ``ReduxKitTesting``

Sugar syntax for testing ReduxKit stores, reducers, and middleware.

## Overview

`ReduxKitTesting` is a test-support library for the `ReduxKit` package. It removes the boilerplate
of asserting unidirectional data flow: instead of hand-rolling `Task { await store.send(...) }` and
reaching for the store's private state, you describe the state you expect after every action — and the
follow-up actions your middleware emits — in a fluent, exhaustive way.

The library is built on three helpers, each matching one layer of the architecture:

- term ``TestStore``: Drives a real `Store` (reducer **and** middleware together) and asserts both the
  immediate state of every action and the follow-up actions middleware dispatches. It also runs the
  store's services, so actions pushed in from outside are asserted the same way.
- term ``ReducerProbe``: Tests a `Reducer` in isolation with a synchronous given/when/then chain.
- term ``MiddlewareProbe``: Tests a `Middleware` in isolation — asserts which action it emits for a
  given state and input action.

Add the product to your test target and import it alongside `ReduxKit`:

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

> Note: `ReduxKitTesting` uses Swift Testing (`@Test`, `#expect`). All failures are reported through
> `Issue.record(_:sourceLocation:)`, so they point at the exact line of the failing assertion.

## A first test

Given a small counter feature:

```swift
struct State: Hashable { var counter = 0 }

enum Action: Actionable {
    case increment, decrement, sideEffect
}

struct CounterReducer: Reducer {
    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .increment: state.counter += 1
        case .decrement: state.counter -= 1
        case .sideEffect: break
        }
        return state
    }
}

// Emits `.increment` as a follow-up when it sees `.sideEffect`.
struct EffectMiddleware: Middleware {
    func process(state: State, with action: Action) async -> Action? {
        action == .sideEffect ? .increment : nil
    }
}
```

A full integration test reads as a sequence of expectations:

```swift
@MainActor
struct CounterTests {
    @Test
    func counterFlow() async {
        let store = TestStore(
            initialState: State(),
            reducer: CounterReducer(),
            middlewares: [EffectMiddleware()]
        )

        // Assert the state produced by the action you send.
        await store.send(.increment) { $0.counter = 1 }
        await store.send(.decrement) { $0.counter = 0 }

        // `.sideEffect` changes nothing directly...
        await store.send(.sideEffect)
        // ...but the middleware dispatched `.increment`, which you must receive.
        await store.receive(.increment) { $0.counter = 1 }

        // Fail the test if any emitted action was left unasserted.
        store.finish()
    }
}
```

## Topics

### Testing a whole store

- ``TestStore``

### Testing in isolation

- ``ReducerProbe``
- ``MiddlewareProbe``
- ``expectReduce(_:from:action:to:sourceLocation:)``

### Articles

- <doc:TestingAStore>
