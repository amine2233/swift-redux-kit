---
name: services
description: Guide to StoreService — registering a long-lived external source (timer, socket, reachability, database, notifications) on a store so its changes are dispatched as actions, plus how it differs from Middleware and how to test it.
---

# Services — Listening to an External Source

`Middleware` reacts to an action and optionally answers with one more action. It is request/response,
scoped to a single action. It cannot subscribe to anything: `Store.send` runs middleware serially, so a
long-lived `for await` inside `process` blocks the store forever.

`StoreService` is the other direction: an outside source pushes, the store receives actions.

| Direction | Type | Lifetime |
|---|---|---|
| action → outside world | `Middleware` | one action |
| outside world → action | `StoreService` | as long as `run()` is awaited |

## The Protocol

```swift
public protocol StoreService<Action>: Sendable {
    associatedtype Action: Sendable & Actionable

    func actions() -> AsyncStream<Action>
}
```

One requirement: hand back the stream of actions the source produces.

## Writing a Service

Wrap the source in an `AsyncStream` and tear it down in `onTermination`:

```swift
struct ReachabilityService: StoreService {
    let monitor: NWPathMonitor

    func actions() -> AsyncStream<AppAction> {
        AsyncStream { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(.reachabilityChanged(path.status == .satisfied))
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: .global())
        }
    }
}
```

A timer-driven service owns its task and cancels it the same way:

```swift
struct RefreshService: StoreService {
    let interval: Duration

    func actions() -> AsyncStream<SearchAction> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    continuation.yield(.refresh)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

When the source already exposes an `AsyncSequence`, skip the type and use `ClosureService`:

```swift
ClosureService { database.changes }
```

## Registering

Declare services next to the store, run them once from the root view:

```swift
@State private var store = SearchStore(
    initialState: .init(),
    reducer: SearchReducer(),
    middlewares: [SearchMiddleware(dependencies: .production)],
    services: [RefreshService(interval: .seconds(60))]
)

var body: some View {
    List(store.repos) { … }
        .task { await store.run() }
}
```

`run()` returns when every service has finished its stream. Cancelling the task that awaits it — which
`.task` does on disappear — tears every service down, so there is nothing to unregister and no `deinit`
bookkeeping. `UndoableStore`, `DescriptiveUndoableStore`, and `ActionableUndoableStore` accept the same
`services:` parameter and expose the same `run()`; actions emitted by their services go through their own
`send(_:)`, so they land in the undo history.

Services not known at construction time run through the `Storeable` overload instead — no registration
needed:

```swift
.task { await store.run(LocationService(), ReachabilityService()) }
```

## Running Without a View

`run()` is a plain `async` method — `.task` is just a convenient owner, not a requirement. Whatever owns
the store's lifetime owns the task.

**App-lifetime singleton store.** Nothing to tear down: the services live as long as the process, so start
them once and never cancel.

```swift
@main
struct MyApp: App {
    init() {
        Task { await AppStore.shared.run() }
    }

    var body: some Scene { WindowGroup { RootView() } }
}
```

**A store whose lifetime you control.** Keep the handle and cancel it when the owner goes away.

```swift
@MainActor
final class Session {
    let store: AppStore
    private var services: Task<Void, Never>?

    func start() {
        services = Task { [store] in await store.run() }
    }

    func stop() {
        services?.cancel()
        services = nil
    }
}
```

**Command-line tool, daemon, or any `async` entry point.** Await it directly — `run()` returns when every
service finishes, so it doubles as the program's main loop.

```swift
@main
struct Tool {
    static func main() async {
        let store = await AppStore(initialState: .init(), reducer: …, middlewares: [], services: [WatchService()])
        await store.run()
    }
}
```

**Alongside other work.** `run()` composes like any child task.

```swift
await withTaskGroup { group in
    group.addTask { await store.run() }
    group.addTask { await server.listen() }
}
```

**Tests.** Own the task, drive the stream, cancel or finish it — see [Testing](#testing) below.

## Starting and Stopping on State

There is no `shouldRun(state:)` hook, and none is needed — key the task on the state that gates it:

```swift
.task(id: store.isAuthenticated) {
    guard store.isAuthenticated else { return }
    await store.run(InboxService())
}
```

## Testing

A service is a plain value producing a stream, so test it directly:

```swift
@Test
func emitsOnEachChange() async {
    let service = ReachabilityService(monitor: stubMonitor)
    var received: [AppAction] = []
    for await action in service.actions().prefix(2) { received.append(action) }
    #expect(received == [.reachabilityChanged(true), .reachabilityChanged(false)])
}
```

For the integration path, register it on a `TestStore`. Emitted actions land in the transition log like
any middleware follow-up, so they are asserted with `receive(_:_:)`:

```swift
@Test
func serviceActionReachesTheStore() async {
    let (stream, continuation) = AsyncStream.makeStream(of: Action.self)
    let store = TestStore(
        initialState: .init(),
        reducer: CounterReducer(),
        middlewares: [],
        services: [ClosureService { stream }]
    )

    let task = Task { await store.run() }
    continuation.yield(.increment)
    continuation.finish()
    await task.value

    await store.receive(.increment) { $0.counter = 1 }
    store.finish()
}
```

Drive the stream from the test and finish it — never rely on wall-clock delays.

## Rules

- One service per external source. Do not multiplex unrelated sources into one stream.
- A service **emits actions only**. It never reads state and never mutates it — that is the reducer's job.
- Reaching out to a service in response to an action stays in `Middleware`. `StoreService` is inbound only.
- Always set `continuation.onTermination` to release the underlying source.
- Finish the stream when the source is exhausted; a service that never finishes runs until its task is
  cancelled, which is the normal case for subscriptions.
