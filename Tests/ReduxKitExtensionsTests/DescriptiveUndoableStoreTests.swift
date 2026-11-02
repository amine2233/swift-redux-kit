import Testing
@testable import ReduxKit
@testable import ReduxKitExtensions

@MainActor
struct DescriptiveUndoableStoreTests {
    struct State: Hashable {
        var counter = 0
        var text = ""
        var items: [String] = []
    }

    enum Action: DescriptiveActionable {
        case increment
        case decrement
        case set(Int)
        case setText(String)
        case addItem(String)
        case removeItem(String)
        case reset

        var undoDescription: String {
            switch self {
            case .increment:
                "Increment"
            case .decrement:
                "Decrement"
            case let .set(value):
                "Set to \(value)"
            case let .setText(text):
                "Set text to '\(text)'"
            case let .addItem(item):
                "Add '\(item)'"
            case let .removeItem(item):
                "Remove '\(item)'"
            case .reset:
                "Reset"
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
            case let .set(value):
                state.counter = value
            case let .setText(text):
                state.text = text
            case let .addItem(item):
                state.items.append(item)
            case let .removeItem(item):
                state.items.removeAll { $0 == item }
            case .reset:
                state.counter = 0
                state.text = ""
                state.items = []
            }
            return state
        }
    }

    // MARK: - Basic Undo/Redo Tests

    @Test
    func basicUndo() async {
        let store = DescriptiveUndoableStore<State, Action>(
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
        let store = DescriptiveUndoableStore<State, Action>(
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

    // MARK: - Description Tests

    @Test
    func nextUndoDescription() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        #expect(store.nextUndoDescription == nil)

        await store.send(.increment)
        #expect(store.nextUndoDescription == "Increment")

        await store.send(.setText("Hello"))
        #expect(store.nextUndoDescription == "Set text to 'Hello'")

        await store.send(.set(42))
        #expect(store.nextUndoDescription == "Set to 42")
    }

    @Test
    func nextRedoDescription() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        #expect(store.nextRedoDescription == nil)

        await store.send(.increment)
        await store.undo()

        #expect(store.nextRedoDescription == "Increment")
    }

    @Test
    func undoDescriptions() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.setText("Test"))
        await store.send(.addItem("Apple"))

        let descriptions = store.undoDescriptions
        #expect(descriptions.count == 3)
        #expect(descriptions[0] == "Add 'Apple'")
        #expect(descriptions[1] == "Set text to 'Test'")
        #expect(descriptions[2] == "Increment")
    }

    @Test
    func redoDescriptions() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.decrement)

        await store.undo()
        await store.undo()

        let descriptions = store.redoDescriptions
        #expect(descriptions.count == 2)
        #expect(descriptions[0] == "Decrement")
        #expect(descriptions[1] == "Increment")
    }

    // MARK: - History Entry Tests

    @Test
    func undoHistory() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.increment)

        let history = store.undoHistory
        #expect(history.count == 2)
        #expect(history[0].state.counter == 0)
        #expect(history[1].state.counter == 1)
        #expect(history[0].undoDescription == "Increment")
        #expect(history[1].undoDescription == "Increment")
    }

    @Test
    func redoHistory() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.increment)
        await store.undo()

        let history = store.redoHistory
        #expect(history.count == 1)
        #expect(history[0].state.counter == 2)
        #expect(history[0].undoDescription == "Increment")
    }

    // MARK: - Multiple Undo/Redo Tests

    @Test
    func undoMultipleSteps() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.increment)
        await store.send(.increment)
        await store.send(.increment)
        await store.send(.increment)

        #expect(store.counter == 5)

        let undoneCount = await store.undo(steps: 3)
        #expect(undoneCount == 3)
        #expect(store.counter == 2)
        #expect(store.undoCount == 2)
        #expect(store.redoCount == 3)
    }

    @Test
    func redoMultipleSteps() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.increment)
        await store.send(.increment)

        await store.undo(steps: 3)
        #expect(store.counter == 0)

        let redoneCount = await store.redo(steps: 2)
        #expect(redoneCount == 2)
        #expect(store.counter == 2)
        #expect(store.undoCount == 2)
        #expect(store.redoCount == 1)
    }

    @Test
    func undoToIndex() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.set(1))
        await store.send(.set(2))
        await store.send(.set(3))
        await store.send(.set(4))
        await store.send(.set(5))

        #expect(store.counter == 5)
        #expect(store.undoCount == 5)

        // Undo to index 2 (should have counter = 2)
        let success = await store.undoToIndex(2)
        #expect(success)
        #expect(store.counter == 2)
        #expect(store.undoCount == 2)
        #expect(store.redoCount == 3)
    }

    @Test
    func undoToInvalidIndex() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)

        let success1 = await store.undoToIndex(-1)
        #expect(!success1)

        let success2 = await store.undoToIndex(10)
        #expect(!success2)

        #expect(store.counter == 1)
    }

    // MARK: - Complex Scenarios

    @Test
    func complexScenarioWithDescriptions() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.addItem("Apple"))
        await store.send(.addItem("Banana"))
        await store.send(.setText("Fruits"))
        await store.send(.increment)

        #expect(store.items.count == 2)
        #expect(store.text == "Fruits")
        #expect(store.counter == 1)

        // Check descriptions
        let descriptions = store.undoDescriptions
        #expect(descriptions[0] == "Increment")
        #expect(descriptions[1] == "Set text to 'Fruits'")
        #expect(descriptions[2] == "Add 'Banana'")
        #expect(descriptions[3] == "Add 'Apple'")

        // Undo text change
        await store.undo()
        #expect(store.counter == 0)
        #expect(store.nextUndoDescription == "Set text to 'Fruits'")

        // Undo text
        await store.undo()
        #expect(store.text == "")

        // Verify redo
        #expect(store.nextRedoDescription == "Set text to 'Fruits'")
        await store.redo()
        #expect(store.text == "Fruits")
    }

    @Test
    func itemManagement() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.addItem("Item 1"))
        await store.send(.addItem("Item 2"))
        await store.send(.addItem("Item 3"))

        #expect(store.items.count == 3)
        #expect(store.undoDescriptions[0] == "Add 'Item 3'")

        await store.send(.removeItem("Item 2"))
        #expect(store.items.count == 2)
        #expect(store.nextUndoDescription == "Remove 'Item 2'")

        await store.undo()
        #expect(store.items.count == 3)
        #expect(store.items.contains("Item 2"))
    }

    // MARK: - History Limit Tests

    @Test
    func historyLimit() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer(),
            historyLimit: 3
        )

        await store.send(.set(1))
        await store.send(.set(2))
        await store.send(.set(3))
        await store.send(.set(4))
        await store.send(.set(5))

        #expect(store.counter == 5)
        #expect(store.undoCount == 3)

        let descriptions = store.undoDescriptions
        #expect(descriptions[0] == "Set to 5")
        #expect(descriptions[1] == "Set to 4")
        #expect(descriptions[2] == "Set to 3")

        await store.undo(steps: 3)
        #expect(store.counter == 2)
    }

    // MARK: - Grouping Tests

    @Test
    func grouping() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        #expect(store.undoCount == 1)

        store.beginGrouping()
        await store.send(.increment)
        #expect(store.counter == 2)
        #expect(store.undoCount == 1)

        await store.undo()
        #expect(store.counter == 0)
    }

    // MARK: - Clear History Tests

    @Test
    func clearHistory() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.increment)
        await store.undo()

        #expect(store.undoCount == 1)
        #expect(store.redoCount == 1)

        store.clearHistory()

        #expect(store.undoCount == 0)
        #expect(store.redoCount == 0)
        #expect(store.nextUndoDescription == nil)
        #expect(store.nextRedoDescription == nil)
        #expect(store.counter == 1)
    }

    // MARK: - Edge Cases

    @Test
    func noOpAction() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.set(0))
        #expect(store.undoCount == 0)

        await store.send(.increment)
        #expect(store.undoCount == 1)
    }

    @Test
    func dynamicMemberLookup() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)
        await store.send(.setText("Test"))
        await store.send(.addItem("Apple"))

        #expect(store.counter == 1)
        #expect(store.text == "Test")
        #expect(store.items.count == 1)
        #expect(store.items[0] == "Apple")
    }

    // MARK: - SwiftUI Binding Tests

#if canImport(SwiftUI)
    @Test
    func binding_extract_embed() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        let binding = store.binding(
            extract: \.counter,
            embed: Action.set
        )

        binding.wrappedValue = 10

        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(store.counter == 10)
        #expect(store.canUndo)
        #expect(store.nextUndoDescription == "Set to 10")

        await store.undo()
        #expect(store.counter == 0)
    }

    @Test
    func binding_keyPath() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        let binding = store.binding(\.counter, send: Action.set)

        binding.wrappedValue = 42

        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(store.counter == 42)
        #expect(store.nextUndoDescription == "Set to 42")
    }
#endif

    // MARK: - Underlying Store Access

    @Test
    func underlyingStoreAccess() async {
        let store = DescriptiveUndoableStore<State, Action>(
            initialState: .init(),
            reducer: TestReducer()
        )

        await store.send(.increment)

        let underlying = store.underlyingStore
        #expect(underlying.counter == 1)

        await underlying.send(.increment)
        #expect(underlying.counter == 2)
        #expect(store.counter == 2)
        #expect(store.undoCount == 1)
    }

    // MARK: - Thread Safety Tests

    @Test
    func threadSafety() async {
        let store = DescriptiveUndoableStore<State, Action>(
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
        #expect(store.undoCount <= 1_000)
    }

    // MARK: - Derived Store Tests

    @Test
    func derivedStore() async {
        let store = DescriptiveUndoableStore<State, Action>(
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
        try? await Task.sleep(nanoseconds: 200_000_000)
        // Derived syncs with parent after undo
        #expect(derived.counter == 2) // Synced with parent
        #expect(store.counter == 2) // Parent unchanged

        await store.undo()
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(store.counter == 1)
        #expect(derived.counter == 1)
    }

    @Test
    func derivedStoreIndependentHistory() async {
        let store = DescriptiveUndoableStore<State, Action>(
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

        // Undo in derived only affects derived history
        await derived.undo()
        try? await Task.sleep(nanoseconds: 200_000_000)
        // Derived syncs with parent after undo
        #expect(derived.counter == 3) // Synced with parent
        #expect(store.counter == 3)
        #expect(store.undoCount == 3)
        #expect(derived.undoCount == 0)
    }
}
