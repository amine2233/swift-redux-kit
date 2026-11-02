import Testing
@testable import ReduxKit

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

    @Test
    func runFeedsRegisteredServicesIntoTheStore() async {
        let (increments, incrementContinuation) = AsyncStream.makeStream(of: Action.self)
        let (additions, additionContinuation) = AsyncStream.makeStream(of: Action.self)

        let store = Store(
            initialState: State(),
            reducer: TestReducer(),
            middlewares: [any Middleware<State, Action>](),
            services: [
                ClosureService { increments },
                ClosureService { additions }
            ]
        )

        let task = Task { await store.run() }

        incrementContinuation.yield(.increment)
        additionContinuation.yield(.add(10))
        incrementContinuation.finish()
        additionContinuation.finish()

        await task.value

        #expect(store.counter == 11)
    }

    @Test
    func runReturnsImmediatelyWithoutRegisteredServices() async {
        let store = Store(
            initialState: State(),
            reducer: TestReducer(),
            middlewares: [any Middleware<State, Action>]()
        )

        await store.run()

        #expect(store.counter == 0)
    }
}
