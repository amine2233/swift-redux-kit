# Testing a Store

Assert state transitions and middleware effects exhaustively with ``TestStore``.

## Overview

A `Store` collapses an entire cascade — the action you send, plus every follow-up a middleware
dispatches — into a single final state. That makes the intermediate steps invisible to a plain
`#expect(store.value == ...)`. ``TestStore`` records every transition the store produces and lets you
walk them one at a time: ``TestStore/send(_:sourceLocation:_:)`` for the action you dispatch, and
``TestStore/receive(_:sourceLocation:_:)`` for each action middleware emits in response.

### How `send` and `receive` divide the work

When you call `await store.send(.sideEffect)`, the reducer runs for `.sideEffect`, then the middleware
runs and may dispatch `.increment`, whose reducer runs too — all before `send` returns. ``TestStore``
records both transitions in order:

```swift
await store.send(.sideEffect)               // consumes the `.sideEffect` transition
await store.receive(.increment) { $0.counter = 1 }   // consumes the follow-up `.increment` transition
```

- `send` asserts the state produced by reducing **only** the action you passed.
- `receive` asserts the next middleware-emitted action, in depth-first dispatch order, and its state.

The trailing closure mutates a copy of the last asserted state to describe what you expect next:

```swift
await store.send(.increment) { $0.counter = 1 }   // expected = currentState with counter set to 1
```

If you expect no state change, omit the closure entirely:

```swift
await store.send(.sideEffect)   // `.sideEffect` does not mutate state on its own
```

### Exhaustivity

By default a ``TestStore`` is exhaustive. Every action the cascade reduces must be consumed by a
matching `receive`; ``TestStore/finish(sourceLocation:)`` records a failure if any are left over.
This is what catches *unexpected* effects — a middleware that fired an action you did not anticipate.

```swift
await store.send(.sideEffect)
// Forgetting `await store.receive(.increment) { ... }` here...
store.finish()                  // ❌ fails: "1 action(s) were emitted but never received: increment"
```

> Important: Exhaustivity is keyed on **reducer invocations**, not on state changes. A follow-up
> action whose reducer leaves the state unchanged still records a transition and must be received.

When you only care about the final outcome, opt out by setting
``TestStore/exhaustivity`` to ``TestStore/Exhaustivity/disabled``. Each `send` then asserts its immediate
transition and silently drains the rest of the cascade:

```swift
let store = TestStore(initialState: State(), reducer: CounterReducer(), middlewares: [EffectMiddleware()])
store.exhaustivity = .disabled

await store.send(.sideEffect)   // drains the follow-up `.increment` without a `receive`
#expect(store.state.counter == 1)
```

### Stores without middleware

Use the convenience initializer when there is nothing to intercept:

```swift
let store = TestStore(initialState: State(), reducer: CounterReducer())
await store.send(.increment) { $0.counter = 1 }
```

### Services

A `StoreService` is the inbound counterpart of a middleware: an external source — a timer, a socket, a
database, a reachability monitor — that pushes actions into the store. Register services on the
``TestStore`` exactly as you would on a `Store`, then start them with ``TestStore/run()``:

```swift
let (stream, continuation) = AsyncStream.makeStream(of: Action.self)
let store = TestStore(
    initialState: State(),
    reducer: CounterReducer(),
    middlewares: [EffectMiddleware()],
    services: [ClosureService { stream }]
)
```

Because nothing in the test *sends* a service's action, there is no `send` to pair it with — the action
arrives on its own and lands in the transition log like any middleware follow-up, so you consume it with
`receive`. Own the task, drive the stream from the test, finish it, and await the run before asserting:

```swift
let task = Task { await store.run() }

continuation.yield(.increment)
continuation.finish()
await task.value

await store.receive(.increment) { $0.counter = 1 }
store.finish()
```

Driving the stream by hand is what keeps the test deterministic. Never let a test depend on a service's
real cadence — a service that sleeps for a minute between emissions makes the test sleep for a minute
too. Give the service its interval as a dependency and pass a tiny one, or replace it with a
`ClosureService` you control, as above.

`run()` returns only once every registered service has finished its stream, and awaiting it is what makes
the assertions deterministic: it is the point at which every emitted action is guaranteed to be in the log.
Asserting while the run task is still live races the service. A production service that never finishes has
no such point — so register a `ClosureService` you finish yourself, and leave the real one on the real
store.

> Important: ``TestStore/send(_:sourceLocation:_:)`` records a failure when transitions are still pending,
> so a service emitting in the background will trip a later `send`. Consume the emissions with `receive`
> first, or set ``TestStore/exhaustivity`` to ``TestStore/Exhaustivity/disabled`` when you only care about
> the final state.

A service needs no store at all to be tested — it is a value producing a stream:

```swift
var received: [Action] = []
for await action in ReachabilityService(monitor: stubMonitor).actions() {
    received.append(action)
    if received.count == 2 { break }
}

#expect(received == [.reachabilityChanged(true), .reachabilityChanged(false)])
```

## Testing layers in isolation

For a focused unit test you do not need a whole store.

A ``ReducerProbe`` chains synchronous given/when/then steps:

```swift
CounterReducer().probe(State(counter: 0))
    .send(.increment)
    .expect(State(counter: 1))
    .send(.increment)
    .expect { #expect($0.counter == 2) }
```

Or assert a single reduction in one line with
``expectReduce(_:from:action:to:sourceLocation:)``:

```swift
expectReduce(CounterReducer(), from: State(counter: 0), action: .increment, to: State(counter: 1))
```

A ``MiddlewareProbe`` asserts which action a middleware emits for a given state and input:

```swift
await EffectMiddleware().probe(state: State())
    .expect(on: .sideEffect, emits: .increment)
    .expectNoAction(on: .increment)
```

## A note on timing

``TestStore/receive(_:sourceLocation:_:)`` never waits or times out — the whole cascade has already
completed inside `send`. The trade-off is that middleware performing real delays (for example
`Task.sleep`) blocks `send` for that wall-clock time. Inject a clock into your middleware's
dependencies if you need tests to stay fast.
