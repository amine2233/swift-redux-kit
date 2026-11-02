import Testing
@testable import ReduxKit
@testable import ReduxKitTesting

@MainActor
struct TestStoreTests {
    struct State: Hashable {
        var counter = 0
    }

    enum Action: Actionable {
        case increment
        case decrement
        case sideEffect
        case set(Int)
    }

    /// Emits `.increment` as a follow-up when it sees `.sideEffect`, otherwise nothing.
    /// Unlike the core suite's middleware it returns immediately so tests stay fast.
    struct EffectMiddleware: Middleware {
        func process(state: State, with action: Action) async -> Action? {
            guard action == .sideEffect else { return nil }

            return .increment
        }
    }

    struct CounterReducer: Reducer {
        func reduce(oldState: State, with action: Action) -> State {
            var state = oldState
            switch action {
            case .increment:
                state.counter += 1
            case .decrement:
                state.counter -= 1
            case let .set(value):
                state.counter = value
            case .sideEffect:
                break
            }
            return state
        }
    }

    private func makeStore() -> TestStore<State, Action> {
        TestStore(
            initialState: .init(),
            reducer: CounterReducer(),
            middlewares: [EffectMiddleware()]
        )
    }

    @Test
    func sendAssertsImmediateState() async {
        let store = makeStore()

        await store.send(.increment) { $0.counter = 1 }
        await store.send(.increment) { $0.counter = 2 }
        await store.send(.decrement) { $0.counter = 1 }

        #expect(store.state.counter == 1)
        store.finish()
    }

    @Test
    func receiveAssertsMiddlewareFollowUp() async {
        let store = makeStore()

        await store.send(.sideEffect)
        await store.receive(.increment) { $0.counter = 1 }

        #expect(store.state.counter == 1)
        store.finish()
    }

    @Test
    func finishFailsWhenFollowUpNotReceived() async {
        let store = makeStore()

        await store.send(.sideEffect)

        withKnownIssue {
            store.finish()
        }
    }

    @Test
    func sendWhilePendingFails() async {
        let store = makeStore()

        await store.send(.sideEffect)

        await withKnownIssue {
            // A follow-up `.increment` is pending and was not received.
            await store.send(.increment) { $0.counter = 1 }
        }
    }

    @Test
    func nonExhaustiveDrainsFollowUps() async {
        let store = makeStore()
        store.exhaustivity = .disabled

        await store.send(.sideEffect)

        // The cascade reduced `.increment`, so the drained state reflects it.
        #expect(store.state.counter == 1)
        store.finish()
    }

    @Test
    func receiveWithoutEmissionFails() async {
        let store = makeStore()

        await store.send(.increment) { $0.counter = 1 }

        await withKnownIssue {
            await store.receive(.increment) { $0.counter = 2 }
        }
    }

    @Test
    func runEmitsServiceActionsAsReceivableFollowUps() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Action.self)
        let store = TestStore(
            initialState: .init(),
            reducer: CounterReducer(),
            middlewares: [EffectMiddleware()],
            services: [ClosureService { stream }]
        )

        let task = Task { await store.run() }
        continuation.yield(.increment)
        continuation.finish()
        await task.value

        await store.receive(.increment) { $0.counter = 1 }

        #expect(store.state.counter == 1)
        store.finish()
    }

    @Test
    func mismatchedStateFails() async {
        let store = makeStore()

        await withKnownIssue {
            await store.send(.increment) { $0.counter = 99 }
        }
    }
}
