import Testing
@testable import ReduxKit

struct PrismTests {
    enum LeftAction: Equatable {
        case action
    }

    enum RightAction: Equatable {
        case action
    }

    enum Action: Equatable {
        case left(LeftAction)
        case right(RightAction)

        static var leftPrism: Prism<Action, LeftAction> {
            Prism(embed: Action.left) {
                guard case let Action.left(action) = $0 else {
                    return nil
                }

                return action
            }
        }
    }

    @Test
    func extract() {
        #expect(Action.leftPrism.extract(Action.right(.action)) == nil)
        #expect(Action.leftPrism.extract(Action.left(.action)) == LeftAction.action)
    }

    @Test
    func embed() {
        #expect(Action.leftPrism.embed(.action) == Action.left(.action))
    }
}
