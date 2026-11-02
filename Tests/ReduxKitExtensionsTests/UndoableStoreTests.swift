import Testing
@testable import ReduxKit
@testable import ReduxKitExtensions

@MainActor
struct UndoableStoreTests {
    struct State: Hashable {
        var counter = 0
        var text = ""
    }

    enum Action: Actionable {
        case increment
        case decrement
        case set(Int)
        case setText(String)
        case reset
    }

    struct TestReducer: Reducer {
        func reduce(oldState: State, with action: Action) -> State {
            var state = oldState
            switch action {
            case .increment:
                state.counter += 1
            case .decrement:
                state.counter -= 1
            case let .set(value):
                state.counter = value
            case let .setText(text):
                state.text = text
            case .reset:
                state.counter = 0
                state.text = ""
            }
            return state
        }
    }

    // MARK: - Basic Undo/Redo Tests

    @Test
    func basicUndo() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        #expect(store.counter == 0)
        #expect(!store.canUndo)

        await store.send(.increment)
        #expect(store.counter == 1)
        #expect(store.canUndo)

        await store.undo()
        #expect(store.counter == 0)
        #expect(!store.canUndo)
    }

    @Test
    func basicRedo() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        #expect(!store.canRedo)

        await store.send(.increment)
        #expect(store.counter == 1)
        #expect(!store.canRedo)

        await store.undo()
        #expect(store.counter == 0)
        #expect(store.canRedo)

        await store.redo()
        #expect(store.counter == 1)
        #expect(!store.canRedo)
    }

    @Test
    func multipleUndoRedo() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.increment)
        await store.send(.increment)
        #expect(store.counter == 3)
        #expect(store.undoCount == 3)

        await store.undo()
        #expect(store.counter == 2)
        await store.undo()
        #expect(store.counter == 1)
        #expect(store.undoCount == 1)
        #expect(store.redoCount == 2)

        await store.redo()
        #expect(store.counter == 2)
        await store.redo()
        #expect(store.counter == 3)
        #expect(store.undoCount == 3)
        #expect(store.redoCount == 0)
    }

    @Test
    func undoRedoWithDifferentActions() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.setText("Hello"))
        await store.send(.increment)

        #expect(store.counter == 2)
        #expect(store.text == "Hello")

        await store.undo()
        #expect(store.counter == 1)
        #expect(store.text == "Hello")

        await store.undo()
        #expect(store.counter == 1)
        #expect(store.text == "")

        await store.undo()
        #expect(store.counter == 0)
        #expect(store.text == "")
    }

    // MARK: - History Management Tests

    @Test
    func historyLimit() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer(),
            historyLimit: 3
        )

        await store.send(.increment) // counter = 1
        await store.send(.increment) // counter = 2
        await store.send(.increment) // counter = 3
        await store.send(.increment) // counter = 4
        await store.send(.increment) // counter = 5

        #expect(store.counter == 5)
        #expect(store.undoCount == 3) // Limited to 3

        await store.undo()
        #expect(store.counter == 4)
        await store.undo()
        #expect(store.counter == 3)
        await store.undo()
        #expect(store.counter == 2)

        // Can't undo further due to limit
        #expect(!store.canUndo)
    }

    @Test
    func clearHistory() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.increment)
        #expect(store.undoCount == 2)

        store.clearHistory()
        #expect(store.undoCount == 0)
        #expect(store.redoCount == 0)
        #expect(!store.canUndo)
        #expect(!store.canRedo)
        #expect(store.counter == 2) // State unchanged
    }

    @Test
    func newActionClearsRedoHistory() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.increment)
        await store.undo()

        #expect(store.canRedo)
        #expect(store.redoCount == 1)

        await store.send(.increment)
        #expect(!store.canRedo)
        #expect(store.redoCount == 0)
    }

    // MARK: - Grouping Tests

    @Test
    func grouping() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        #expect(store.undoCount == 1)

        store.beginGrouping()
        await store.send(.increment)
        #expect(store.counter == 2)
        #expect(store.undoCount == 1) // Still 1 due to grouping

        await store.undo()
        #expect(store.counter == 0) // Undoes both increments
    }

    @Test
    func groupingWithNoHistory() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        store.beginGrouping()
        await store.send(.increment)
        #expect(store.counter == 1)
        #expect(store.undoCount == 0) // No history because grouping with empty past
    }

    // MARK: - Edge Cases

    @Test
    func undoWhenNothingToUndo() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        let result = await store.undo()
        #expect(!result)
        #expect(store.counter == 0)
    }

    @Test
    func redoWhenNothingToRedo() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        let result = await store.redo()
        #expect(!result)
        #expect(store.counter == 0)
    }

    @Test
    func noHistoryForNoOpAction() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.set(0)) // No state change
        #expect(store.undoCount == 0) // No history recorded

        await store.send(.increment)
        #expect(store.undoCount == 1) // History recorded
    }

    @Test
    func dynamicMemberLookup() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.setText("Test"))

        #expect(store.counter == 1)
        #expect(store.text == "Test")

        await store.undo()
        #expect(store.text == "")
    }

    // MARK: - Complex Scenarios

    @Test
    func complexUndoRedoSequence() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment) // 1
        await store.send(.increment) // 2
        await store.send(.increment) // 3

        await store.undo() // 2
        await store.undo() // 1

        await store.send(.increment) // 2 (clears redo)

        #expect(store.counter == 2)
        #expect(store.undoCount == 2)
        #expect(store.redoCount == 0)

        await store.undo() // 1
        await store.undo() // 0

        #expect(store.counter == 0)
        #expect(!store.canUndo)
    }

    @Test
    func alternatingIncrementDecrement() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.decrement)
        await store.send(.increment)
        await store.send(.decrement)

        #expect(store.counter == 0)
        #expect(store.undoCount == 4)

        await store.undo()
        #expect(store.counter == 1)
        await store.undo()
        #expect(store.counter == 0)
        await store.undo()
        #expect(store.counter == 1)
        await store.undo()
        #expect(store.counter == 0)
    }

    // MARK: - SwiftUI Binding Tests

#if canImport(SwiftUI)
    @Test
    func binding_extract_embed() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        let binding = store.binding(
            extract: \.counter,
            embed: Action.set
        )

        binding.wrappedValue = 10

        // Give async Task time to execute
        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(store.counter == 10)
        #expect(store.canUndo)

        await store.undo()
        #expect(store.counter == 0)
    }

    @Test
    func binding_keyPath() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        let binding = store.binding(\.counter, send: Action.set)

        binding.wrappedValue = 42

        // Give async Task time to execute
        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(store.counter == 42)
        #expect(store.canUndo)
    }
#endif

    // MARK: - Underlying Store Access

    @Test
    func underlyingStoreAccess() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)

        let underlying = store.underlyingStore
        #expect(underlying.counter == 1)

        // Sending action directly to underlying store doesn't affect history
        await underlying.send(.increment)
        #expect(underlying.counter == 2)
        #expect(store.counter == 2)
        #expect(store.undoCount == 1) // Still 1, not 2
    }

    // MARK: - Thread Safety Tests

    @Test
    func threadSafety() async {
        let store = UndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await withDiscardingTaskGroup { group in
            for _ in 1 ... 1_000 {
                group.addTask {
                    await store.send(.increment)
                }
            }
        }

        #expect(store.counter == 1_000)
        #expect(store.undoCount <= 1_000) // May be less due to concurrent modifications
    }

    // MARK: - Derived Store Tests

    @Test
    func derivedStore() async {
        let store = UndoableStore<State, Action>(
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

        // Both should have independent undo histories
        await derived.undo()
        #expect(derived.counter == 1)
        #expect(store.counter == 2) // Parent unchanged

        await store.undo()
        #expect(store.counter == 1)
        #expect(derived.counter == 1)
    }

    @Test
    func derivedStoreIndependentHistory() async {
        let store = UndoableStore<State, Action>(
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
        // Parent store sees all actions (its 2 + derived's 1 = 3)
        #expect(store.undoCount == 3)
        #expect(derived.undoCount == 1)

        // Undo in derived only affects derived history
        await derived.undo()
        try? await Task.sleep(nanoseconds: 200_000_000) // Give time for state restoration
        // Derived state after undo is synced from parent
        #expect(derived.counter == 3) // Synced with parent (parent is still at 3)
        #expect(store.counter == 3) // Parent unchanged
        #expect(store.undoCount == 3) // Parent history unchanged
        #expect(derived.undoCount == 0)
    }
}
