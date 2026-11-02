import Testing
@testable import ReduxKit
@testable import ReduxKitExtensions

@MainActor
struct StoreServiceTests {
    struct State: Hashable {
        var counter = 0
    }

    enum Action: Actionable {
        case increment
        case add(Int)
    }

    struct TestReducer: Reducer {
        func reduce(oldState: State, with action: Action) -> State {
            var state = oldState
            switch action {
            case .increment:
                state.counter += 1
            case let .add(value):
                state.counter += value
            }
            return state
        }
    }

    private func makeStore() -> Store<State, Action> {
        Store(
            initialState: State(),
            reducer: TestReducer(),
            middlewares: [any Middleware<State, Action>]()
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0 ..< 500 where !condition() {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    @Test
    func forwardsEveryEmittedActionAndReturnsWhenTheStreamFinishes() async {
        let store = makeStore()
        let (stream, continuation) = AsyncStream.makeStream(of: Action.self)

        let task = Task { await store.run(ClosureService { stream }) }

        continuation.yield(.increment)
        continuation.yield(.increment)
        continuation.yield(.increment)
        continuation.finish()

        await task.value

        #expect(store.counter == 3)
    }

    @Test
    func cancellationTearsTheServiceDown() async {
        let store = makeStore()
        let (stream, continuation) = AsyncStream.makeStream(of: Action.self)
        let (terminations, terminationContinuation) = AsyncStream.makeStream(of: Void.self)
        continuation.onTermination = { _ in terminationContinuation.finish() }

        let task = Task { await store.run(ClosureService { stream }) }

        continuation.yield(.increment)
        await waitUntil { store.counter == 1 }

        task.cancel()
        await task.value

        for await _ in terminations {}

        continuation.yield(.increment)
        try? await Task.sleep(for: .milliseconds(20))

        #expect(store.counter == 1)
    }

    @Test
    func runsEveryServiceAndReturnsOnlyWhenAllOfThemFinish() async {
        let store = makeStore()
        let (increments, incrementContinuation) = AsyncStream.makeStream(of: Action.self)
        let (additions, additionContinuation) = AsyncStream.makeStream(of: Action.self)

        let task = Task {
            await store.run(
                ClosureService { increments },
                ClosureService { additions }
            )
        }

        incrementContinuation.yield(.increment)
        await waitUntil { store.counter == 1 }
        incrementContinuation.finish()

        additionContinuation.yield(.add(10))
        additionContinuation.finish()
        await task.value

        #expect(store.counter == 11)
    }
}
