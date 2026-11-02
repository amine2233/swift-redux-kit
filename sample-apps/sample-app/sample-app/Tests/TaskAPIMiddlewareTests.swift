import ReduxKit
import ReduxKitExtensions
import ReduxKitTesting
import Testing
@testable import sample_app

// Examples of testing a real middleware with `ReduxKitTesting`.
//
// `TaskAPIMiddleware` (from ActionableUndoableExample) intercepts task actions, performs a mock API
// call, and dispatches a `.logAPICall` follow-up. These tests use `MiddlewareProbe` to assert the
// emitted action in isolation, and a `TestStore` to assert the full reducer + middleware flow.

@MainActor
struct TaskAPIMiddlewareTests {
    private let task = TaskExample(id: "1", title: "Write tests")

    // MARK: - MiddlewareProbe: emitted follow-up actions

    @Test
    func createTaskEmitsLog() async {
        await TaskAPIMiddleware().probe(state: TaskState())
            .expect(
                on: .createTask(id: "1", title: "Write tests"),
                emits: .logAPICall("✅ API: Created 'Write tests'")
            )
    }

    @Test
    func deleteTaskEmitsLog() async {
        await TaskAPIMiddleware().probe(state: TaskState(tasks: [task]))
            .expect(
                on: .deleteTask(task: task),
                emits: .logAPICall("🗑️ API: Deleted 'Write tests'")
            )
    }

    @Test
    func updateTaskEmitsLog() async {
        await TaskAPIMiddleware().probe(state: TaskState(tasks: [task]))
            .expect(
                on: .updateTask(id: "1", title: "Write more tests", oldTitle: "Write tests"),
                emits: .logAPICall("📝 API: Updated to 'Write more tests'")
            )
    }

    // MARK: - State-dependent behavior

    @Test
    func toggleEmitsLogWhenTaskExists() async {
        // The middleware reads `state.tasks` to find the task title, so the probe state must contain it.
        await TaskAPIMiddleware().probe(state: TaskState(tasks: [task]))
            .expect(
                on: .toggleTask(id: "1", oldValue: false),
                emits: .logAPICall("✓ API: Toggled 'Write tests'")
            )
    }

    @Test
    func toggleEmitsNothingWhenTaskMissing() async {
        // No matching task in state → the middleware returns nil and the chain stops.
        await TaskAPIMiddleware().probe(state: TaskState())
            .expectNoAction(on: .toggleTask(id: "missing", oldValue: false))
    }

    // MARK: - Ignored actions

    @Test
    func nonAPIActionsEmitNothing() async {
        await TaskAPIMiddleware().probe(state: TaskState())
            .expectNoAction(on: .clearCompleted(tasks: []))
            .expectNoAction(on: .logAPICall("already logged"))
    }

    // MARK: - TestStore: full reducer + middleware flow

    @Test
    func createTaskUpdatesStateThenLogsViaMiddleware() async {
        let store = TestStore(
            initialState: TaskState(),
            reducer: TaskReducer(),
            middlewares: [TaskAPIMiddleware()]
        )

        // The reducer appends the task synchronously...
        await store.send(.createTask(id: "1", title: "Write tests")) {
            $0.tasks = [task]
        }
        // ...then the middleware's API call dispatches a `.logAPICall` follow-up.
        await store.receive(.logAPICall("✅ API: Created 'Write tests'")) {
            $0.apiCallLog = ["✅ API: Created 'Write tests'"]
        }

        store.finish()
    }
}
