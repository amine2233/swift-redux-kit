import Testing
@testable import ReduxKit
@testable import ReduxKitExtensions

@MainActor
struct ActionableUndoableStoreTests {
    struct State: UndoableState {
        var counter = 0
        var text = ""
    }

    enum Action: InvertibleActionable {
        typealias State = ActionableUndoableStoreTests.State

        case increment
        case decrement
        case set(Int, oldValue: Int)
        case setText(String, oldValue: String)
        case reset(oldCounter: Int, oldText: String)

        func inverse(state: State) -> Self? {
            switch self {
            case .increment:
                .decrement
            case .decrement:
                .increment
            case let .set(_, oldValue):
                .set(oldValue, oldValue: oldValue)
            case let .setText(_, oldValue):
                .setText(oldValue, oldValue: oldValue)
            case let .reset(oldCounter, oldText):
                .set(oldCounter, oldValue: 0)
            }
        }

        var undoDescription: String {
            switch self {
            case .increment: "Increment"
            case .decrement: "Decrement"
            case .set: "Set Value"
            case .setText: "Set Text"
            case .reset: "Reset"
            }
        }
    }

    struct TestReducer: Reducer {
        func reduce(oldState: State, with action: Action) -> State {
            var state = oldState
            switch action {
            case .increment:
                state.counter += 1
            case .decrement:
                state.counter -= 1
            case let .set(value, _):
                state.counter = value
            case let .setText(text, _):
                state.text = text
            case .reset:
                state.counter = 0
                state.text = ""
            }
            return state
        }
    }

    // MARK: - Derived Store Tests

    @Test
    func derivedStore() async {
        let store = ActionableUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        // Create a derived store that mirrors the parent
        let derived = store.derived(
            deriveState: { $0 },
            deriveAction: { $0 }
        )

        // Initial state should match
        #expect(store.counter == 0)
        #expect(derived.counter == 0)

        // Send action to parent
        await store.send(.increment)
        #expect(store.counter == 1)

        // Derived should update automatically
        try? await Task.sleep(nanoseconds: 100_000_000) // Give time for observation
        #expect(derived.counter == 1)

        // Send action to derived (should propagate to parent)
        await derived.send(.increment)
        #expect(derived.counter == 2)
        #expect(store.counter == 2)

        // ActionableUndoableStore: undo dispatches inverse action
        // So derived undo affects parent state (inverse action is sent)
        await derived.undo()
        #expect(derived.counter == 1)
        #expect(store.counter == 1) // Parent affected by inverse action

        await store.undo()
        #expect(store.counter == 2) // Undo of inverse = increment
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(derived.counter == 2)
    }

    @Test
    func derivedStoreIndependentHistory() async {
        let store = ActionableUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        let derived = store.derived(
            deriveState: { $0 },
            deriveAction: { $0 }
        )

        // Perform actions on both stores
        await store.send(.increment)
        await store.send(.increment)
        #expect(store.counter == 2)

        await derived.send(.increment)
        #expect(derived.counter == 3)
        #expect(store.counter == 3)

        // Each store tracks its own history
        #expect(store.undoCount == 3)
        #expect(derived.undoCount == 1)

        // Undo in derived dispatches inverse action to parent
        await derived.undo()
        #expect(derived.counter == 2)
        #expect(store.counter == 2) // Parent IS affected because inverse action is dispatched
        #expect(store.undoCount == 4) // Parent history now includes the inverse action
        #expect(derived.undoCount == 0)
    }

    @Test
    func derivedStorePreservesInvertibility() async {
        let store = ActionableUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        let derived = store.derived(
            deriveState: { $0 },
            deriveAction: { $0 }
        )

        // Perform multiple actions
        await derived.send(.increment)
        await derived.send(.increment)
        await derived.send(.increment)

        #expect(derived.counter == 3)
        #expect(derived.canUndo)

        // Undo all actions (inverse actions should work)
        await derived.undo()
        #expect(derived.counter == 2)

        await derived.undo()
        #expect(derived.counter == 1)

        await derived.undo()
        #expect(derived.counter == 0)

        #expect(!derived.canUndo)
    }
}
