import Testing
@testable import ReduxKit

struct MiddlewareTests {
    struct State: Hashable {
        var counter: Int
    }

    enum Action: Actionable {
        case increment
        case decrement
    }

    typealias Dependencies = Void

    struct CounterMiddleware: Middleware {
        func process(state: State, with action: Action) async -> Action? {
            switch action {
            case .increment: .decrement
            case .decrement: .increment
            }
        }
    }

    @Test
    func optional() async {
        let state: State? = .init(counter: 1)

        let optional = CounterMiddleware().optional()
        let nextAction = await optional.process(state: nil, with: .increment)
        #expect(nextAction == nil)

        let anotherAction = await optional.process(state: state, with: .increment)
        #expect(anotherAction == .decrement)
    }

    @Test
    func lifted() async {
        struct LiftedState: Hashable {
            var state = State(counter: 1)
        }

        enum LiftedAction: Actionable {
            case action(Action)

            static var prism: Prism<LiftedAction, Action> {
                .init(embed: LiftedAction.action) {
                    guard case let LiftedAction.action(action) = $0 else {
                        return nil
                    }

                    return action
                }
            }
        }

        typealias LiftedDependencies = Void

        let lifted = CounterMiddleware().lifted(
            keyPath: \LiftedState.state,
            prism: LiftedAction.prism
        )

        let nextAction = await lifted.process(state: .init(), with: .action(.increment))
        #expect(nextAction == .action(.decrement))
    }

    @Test
    func keyed() async {
        struct KeyedState: Hashable {
            var keyed = ["key": State(counter: 1)]
        }

        enum KeyedAction: Actionable {
            case action(String, Action)

            static var prism: Prism<KeyedAction, (String, Action)> {
                .init(embed: KeyedAction.action) {
                    guard case let KeyedAction.action(key, action) = $0 else {
                        return nil
                    }

                    return (key, action)
                }
            }
        }

        let keyed = CounterMiddleware().keyed(
            keyPath: \KeyedState.keyed,
            prism: KeyedAction.prism
        )

        let nextAction = await keyed.process(state: .init(), with: .action("key", .increment))
        #expect(nextAction == .action("key", .decrement))

        let nilAction = await keyed.process(state: .init(), with: .action("key1", .increment))
        #expect(nilAction == nil)
    }

    @Test
    func offset() async {
        struct OffsetState: Hashable {
            var state: [State] = [.init(counter: 1)]
        }

        enum OffsetAction: Actionable {
            case action(Int, Action)

            static var prism: Prism<OffsetAction, (Int, Action)> {
                .init(embed: OffsetAction.action) {
                    guard case let OffsetAction.action(offset, action) = $0 else {
                        return nil
                    }

                    return (offset, action)
                }
            }
        }

        typealias OffsetDependencies = Void

        let offset = CounterMiddleware().offset(
            keyPath: \OffsetState.state,
            prism: OffsetAction.prism
        )

        let nextAction = await offset.process(state: .init(), with: .action(0, .increment))
        #expect(nextAction == .action(0, .decrement))
    }
}
