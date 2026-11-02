import Testing
@testable import ReduxKit
@testable import ReduxKitTesting

// MARK: - Example feature under test

// A small, self-contained "todos" feature used to demonstrate how to test a ReduxKit feature with
// `ReduxKitTesting`. It mirrors the shape of a real feature: a value-type state, an enum of actions,
// a pure reducer, and an async middleware that loads data through an injected dependency.

private struct Todo: Hashable, Sendable {
    let id: Int
    var title: String
    var isDone: Bool = false
}

private struct TodosState: Hashable, Sendable {
    var todos: [Todo] = []
    var isLoading = false
}

private enum TodosAction: Actionable {
    case load
    case loaded([Todo])
    case add(String)
    case toggle(id: Int)
}

private struct TodosReducer: Reducer {
    func reduce(oldState: TodosState, with action: TodosAction) -> TodosState {
        var state = oldState
        switch action {
        case .load:
            state.isLoading = true
        case let .loaded(todos):
            state.todos = todos
            state.isLoading = false
        case let .add(title):
            let nextID = (state.todos.map(\.id).max() ?? 0) + 1
            state.todos.append(Todo(id: nextID, title: title))
        case let .toggle(id):
            if let index = state.todos.firstIndex(where: { $0.id == id }) {
                state.todos[index].isDone.toggle()
            }
        }
        return state
    }
}

/// Loads todos through an injected closure when it sees `.load`, then dispatches `.loaded`.
/// Every other action is ignored (returns `nil`, stopping the chain).
private struct TodosMiddleware: Middleware {
    let fetch: @Sendable () async -> [Todo]

    func process(state: TodosState, with action: TodosAction) async -> TodosAction? {
        guard case .load = action else { return nil }

        return await .loaded(fetch())
    }
}

// MARK: - Example tests

@MainActor
struct ExampleUsageTests {
    private let sample = [
        Todo(id: 1, title: "Buy milk"),
        Todo(id: 2, title: "Walk the dog", isDone: true)
    ]

    private func makeStore(loading: [Todo] = []) -> TestStore<TodosState, TodosAction> {
        TestStore(
            initialState: .init(),
            reducer: TodosReducer(),
            middlewares: [TodosMiddleware(fetch: { loading })]
        )
    }

    /// 1. `TestStore` — full integration. Assert the state of the action you send, then the follow-up
    /// action the middleware emits. `finish()` proves nothing else was dispatched.
    @Test
    func loadingTodosFlow() async {
        let store = makeStore(loading: sample)

        // `.load` flips `isLoading` synchronously in the reducer.
        await store.send(.load) { $0.isLoading = true }

        // The middleware fetched the todos and dispatched `.loaded`.
        await store.receive(.loaded(sample)) {
            $0.todos = sample
            $0.isLoading = false
        }

        store.finish()
    }

    /// A store with no middleware needs no `receive` — use the convenience initializer.
    @Test
    func addingAndTogglingTodos() async {
        let store = TestStore(initialState: .init(), reducer: TodosReducer())

        await store.send(.add("Buy milk")) {
            $0.todos = [Todo(id: 1, title: "Buy milk")]
        }
        await store.send(.toggle(id: 1)) {
            $0.todos[0].isDone = true
        }

        store.finish()
    }

    /// Non-exhaustive mode: the sent action's own transition is still asserted, but middleware
    /// follow-ups are drained silently — handy when you only care about the final state.
    @Test
    func nonExhaustiveSkipsFollowUps() async {
        let store = makeStore(loading: sample)
        store.exhaustivity = .disabled

        await store.send(.load) { $0.isLoading = true } // `.loaded` follow-up drained, no `receive` needed

        #expect(store.state.todos == sample)
        #expect(store.state.isLoading == false)
        store.finish() // passes even though `.loaded` was never received
    }

    /// 2. `ReducerProbe` — pure, synchronous reducer logic, no store or middleware.
    @Test
    func reducerProbeChain() {
        TodosReducer().probe(TodosState())
            .send(.add("First"))
            .expect { #expect($0.todos.map(\.title) == ["First"]) }
            .send(.add("Second"))
            .expect { #expect($0.todos.count == 2) }
            .send(.toggle(id: 2))
            .expect { #expect($0.todos[1].isDone) }
    }

    /// `expectReduce` is the one-liner for a single reduction with `Equatable` state.
    @Test
    func reducerOneLiner() {
        expectReduce(
            TodosReducer(),
            from: TodosState(),
            action: .loaded(sample),
            to: TodosState(todos: sample, isLoading: false)
        )
    }

    /// 3. `MiddlewareProbe` — assert which action the middleware emits for a given input.
    @Test
    func middlewareProbeEmissions() async {
        await TodosMiddleware(fetch: { sample }).probe(state: TodosState())
            .expect(on: .load, emits: .loaded(sample)) // `.load` triggers a fetch...
            .expectNoAction(on: .loaded(sample)) // ...handled actions stop the chain
    }
}
