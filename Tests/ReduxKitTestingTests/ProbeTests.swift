import Testing
@testable import ReduxKit
@testable import ReduxKitTesting

struct ReducerProbeTests {
    struct State: Hashable {
        var counter = 0
    }

    enum Action: Actionable {
        case increment
        case decrement
        case set(Int)
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
            }
            return state
        }
    }

    @Test
    func fluentChaining() {
        CounterReducer().probe(State(counter: 0))
            .send(.increment)
            .expect(State(counter: 1))
            .send(.increment)
            .expect { #expect($0.counter == 2) }
            .send(.set(10))
            .expect(State(counter: 10))
    }

    @Test
    func oneLiner() {
        expectReduce(
            CounterReducer(),
            from: State(counter: 0),
            action: .increment,
            to: State(counter: 1)
        )
    }

    @Test
    func mismatchFails() {
        withKnownIssue {
            CounterReducer().probe(State(counter: 0))
                .send(.increment)
                .expect(State(counter: 5))
        }
    }
}

@MainActor
struct MiddlewareProbeTests {
    struct State: Hashable {
        var counter = 0
    }

    enum Action: Actionable {
        case increment
        case sideEffect
    }

    struct EffectMiddleware: Middleware {
        func process(state: State, with action: Action) async -> Action? {
            guard action == .sideEffect else { return nil }

            return .increment
        }
    }

    @Test
    func emitsExpectedAction() async {
        await EffectMiddleware().probe(state: State())
            .expect(on: .sideEffect, emits: .increment)
            .expectNoAction(on: .increment)
    }

    @Test
    func mismatchFails() async {
        await withKnownIssue {
            await EffectMiddleware().probe(state: State())
                .expect(on: .sideEffect, emits: nil)
        }
    }
}
