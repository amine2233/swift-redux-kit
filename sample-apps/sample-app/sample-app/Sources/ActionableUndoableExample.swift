import Foundation
import ReduxKit
import ReduxKitExtensions
import SwiftUI

// MARK: - Actionable Undoable Store Example: Task Manager with API Integration

// This example demonstrates how to use ActionableUndoableStore to add undo/redo functionality
// with middleware support for reversing API calls.
//
// The problem:
// - Users want to undo/redo their actions
// - Actions trigger API requests (create, update, delete)
// - When undoing, we need to reverse the API operation (e.g., delete becomes create)
// - Middleware needs to intercept undo/redo to make API calls
//
// The solution:
// - Use ActionableUndoableStore which dispatches inverse actions through middleware
// - Implement InvertibleActionable protocol to provide inverse actions
// - Middleware intercepts both original and inverse actions
// - API calls are automatically reversed on undo/redo

// MARK: - Task Model

/// A task in the task manager
struct TaskExample: Sendable, Hashable, Identifiable {
    let id: String
    var title: String
    var isCompleted: Bool

    init(id: String = UUID().uuidString, title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

// MARK: - State

/// Task manager state - conforms to UndoableState for undo/redo support
struct TaskState: UndoableState {
    var tasks: [TaskExample] = []
    var apiCallLog: [String] = [] // For demo purposes: shows API calls made

    var completedCount: Int {
        tasks.filter(\.isCompleted).count
    }

    var pendingCount: Int {
        tasks.count - completedCount
    }
}

// MARK: - Actions

/// Task actions that can be undone by dispatching inverse actions
enum TaskAction: InvertibleActionable {
    typealias State = TaskState

    case createTask(id: String, title: String)
    case deleteTask(task: TaskExample) // Store full task to enable undo
    case updateTask(id: String, title: String, oldTitle: String)
    case toggleTask(id: String, oldValue: Bool)
    case clearCompleted(tasks: [TaskExample]) // Store tasks to enable undo

    /// Log action (not undoable - used to record API calls for demo)
    case logAPICall(String)

    /// Returns the inverse action that reverses this action's effects.
    /// Now with type-safe access to TaskState!
    func inverse(state: TaskState) -> Self? {
        switch self {
        case let .createTask(id, title):
            // To undo create, we need to delete with the full task
            // We can access the state to get the actual task if needed
            let task = TaskExample(id: id, title: title, isCompleted: false)
            return .deleteTask(task: task)

        case let .deleteTask(task):
            // To undo delete, recreate the task with its original state
            return .createTask(id: task.id, title: task.title)

        case let .updateTask(id, _, oldTitle):
            // To undo update, restore the old title
            return .updateTask(id: id, title: oldTitle, oldTitle: oldTitle)

        case let .toggleTask(id, oldValue):
            // To undo toggle, toggle back to old value
            // We can access state.tasks here if we need to verify the task exists
            return .toggleTask(id: id, oldValue: !oldValue)

        case let .clearCompleted(tasks):
            // To undo clear, recreate all the cleared tasks
            // We'll use the first task's inverse as representative
            // In reality, you'd need to handle multiple actions
            return tasks.first.map { .createTask(id: $0.id, title: $0.title) }

        case .logAPICall:
            // Logging is not undoable
            return nil
        }
    }

    var undoDescription: String {
        switch self {
        case .createTask:
            "Create Task"
        case .deleteTask:
            "Delete Task"
        case .updateTask:
            "Update Task"
        case .toggleTask:
            "Toggle Task"
        case .clearCompleted:
            "Clear Completed"
        case .logAPICall:
            "Log API Call"
        }
    }
}

// MARK: - Reducer

struct TaskReducer: Reducer {
    func reduce(oldState: TaskState, with action: TaskAction) -> TaskState {
        var state = oldState

        switch action {
        case let .createTask(id, title):
            let task = TaskExample(id: id, title: title)
            state.tasks.append(task)

        case let .deleteTask(task):
            state.tasks.removeAll { $0.id == task.id }

        case let .updateTask(id, title, _):
            if let index = state.tasks.firstIndex(where: { $0.id == id }) {
                state.tasks[index].title = title
            }

        case let .toggleTask(id, _):
            if let index = state.tasks.firstIndex(where: { $0.id == id }) {
                state.tasks[index].isCompleted.toggle()
            }

        case let .clearCompleted(tasks):
            state.tasks.removeAll { task in
                tasks.contains { $0.id == task.id }
            }

        case let .logAPICall(message):
            state.apiCallLog.append(message)
        }

        return state
    }
}

// MARK: - Middleware

/// Mock API service for demonstration
actor MockAPIService {
    func createTask(id: String, title: String) async {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        print("📡 API: Created task '\(title)' (id: \(id))")
    }

    func deleteTask(id: String) async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        print("📡 API: Deleted task (id: \(id))")
    }

    func updateTask(id: String, title: String) async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        print("📡 API: Updated task to '\(title)' (id: \(id))")
    }

    func toggleTask(id: String, isCompleted: Bool) async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        print("📡 API: Toggled task completion to \(isCompleted) (id: \(id))")
    }
}

/// Middleware that makes API calls for task actions
struct TaskAPIMiddleware: Middleware {
    let api = MockAPIService()

    func process(state: TaskState, with action: TaskAction) async -> TaskAction? {
        switch action {
        case let .createTask(id, title):
            await api.createTask(id: id, title: title)
            return .logAPICall("✅ API: Created '\(title)'")

        case let .deleteTask(task):
            await api.deleteTask(id: task.id)
            return .logAPICall("🗑️ API: Deleted '\(task.title)'")

        case let .updateTask(id, title, _):
            await api.updateTask(id: id, title: title)
            return .logAPICall("📝 API: Updated to '\(title)'")

        case let .toggleTask(id, _):
            if let task = state.tasks.first(where: { $0.id == id }) {
                await api.toggleTask(id: id, isCompleted: task.isCompleted)
                return .logAPICall("✓ API: Toggled '\(task.title)'")
            }

        case .clearCompleted, .logAPICall:
            break
        }

        return nil
    }
}

/// Lifecycle middleware that logs undo/redo events
struct UndoRedoLoggerMiddleware: Middleware {
    func process(
        state: TaskState,
        with action: UndoRedoLifecycleAction<TaskAction>
    ) async -> UndoRedoLifecycleAction<TaskAction>? {
        switch action {
        case let .willUndo(originalAction):
            print("⏪ UNDO: About to undo '\(originalAction.undoDescription)'")

        case let .didUndo(originalAction):
            print("⏪ UNDO: Finished undoing '\(originalAction.undoDescription)'")

        case let .willRedo(originalAction):
            print("⏩ REDO: About to redo '\(originalAction.undoDescription)'")

        case let .didRedo(originalAction):
            print("⏩ REDO: Finished redoing '\(originalAction.undoDescription)'")
        }

        return nil
    }
}

// MARK: - SwiftUI Example View

struct ActionableUndoableExampleView: View {
    @State private var store = ActionableUndoableStore(
        initialState: TaskState(),
        reducer: TaskReducer(),
        middlewares: [TaskAPIMiddleware()],
        historyLimit: 20,
        lifecycleMiddlewares: [UndoRedoLoggerMiddleware()]
    )

    @State private var newTaskTitle: String = ""
    @State private var showingAPILog: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with undo/redo
            toolbarSection

            Divider()

            // Main content
            ScrollView {
                VStack(spacing: 16) {
                    // Add task section
                    addTaskSection

                    // Stats
                    statsSection

                    // Task list
                    taskListSection

                    // API log toggle
                    apiLogSection

                    // Explanation
                    explanationSection
                }
                .padding()
            }
        }
        .navigationTitle("Actionable Undo: Tasks")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var toolbarSection: some View {
        HStack(spacing: 16) {
            // Undo/Redo buttons
            HStack(spacing: 8) {
                Button {
                    store.undoDispatch()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.title3)
                        if let description = store.nextUndoDescription {
                            Text(description)
                                .font(.caption2)
                        }
                    }
                }
                .disabled(!store.canUndo)

                Button {
                    store.redoDispatch()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.title3)
                        if let description = store.nextRedoDescription {
                            Text(description)
                                .font(.caption2)
                        }
                    }
                }
                .disabled(!store.canRedo)
            }

            Divider()
                .frame(height: 50)

            // History stats
            VStack(alignment: .leading, spacing: 2) {
                Text("History:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label("\(store.undoCount)", systemImage: "arrow.uturn.backward")
                    Label("\(store.redoCount)", systemImage: "arrow.uturn.forward")
                }
                .font(.caption2)
            }

            Spacer()

            // Clear completed
            Button {
                Task {
                    let completedTasks = store.tasks.filter(\.isCompleted)
                    await store.send(.clearCompleted(tasks: completedTasks))
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Clear Done")
                }
                .font(.caption)
            }
            .disabled(store.completedCount == 0)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }

    private var addTaskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add New Task")
                .font(.headline)

            HStack {
                TextField("Task title...", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task {
                        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }

                        await store.send(.createTask(id: UUID().uuidString, title: title))
                        newTaskTitle = ""
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statsSection: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Total",
                value: "\(store.tasks.count)",
                icon: "list.bullet",
                color: .blue
            )

            StatCard(
                title: "Pending",
                value: "\(store.pendingCount)",
                icon: "circle",
                color: .orange
            )

            StatCard(
                title: "Done",
                value: "\(store.completedCount)",
                icon: "checkmark.circle.fill",
                color: .green
            )
        }
    }

    private var taskListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tasks")
                .font(.headline)

            if store.tasks.isEmpty {
                Text("No tasks yet. Add one above!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(store.tasks) { task in
                    TaskRow(
                        task: task,
                        onToggle: {
                            store.dispatch(.toggleTask(id: task.id, oldValue: task.isCompleted))
                        },
                        onDelete: {
                            store.dispatch(.deleteTask(task: task))
                        }
                    )
                }
            }
        }
    }

    private var apiLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showingAPILog.toggle()
            } label: {
                HStack {
                    Text("API Call Log (\(store.apiCallLog.count))")
                        .font(.headline)
                    Spacer()
                    Image(systemName: showingAPILog ? "chevron.up" : "chevron.down")
                }
            }

            if showingAPILog {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if store.apiCallLog.isEmpty {
                            Text("No API calls yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(store.apiCallLog.enumerated()), id: \.offset) { index, log in
                                Text("\(index + 1). \(log)")
                                    .font(.caption)
                                    .monospaced()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How ActionableUndoableStore Works:")
                .font(.headline)

            Group {
                Text("🔄 Dispatches inverse actions through middleware")
                Text("📡 Middleware intercepts undo/redo to reverse API calls")
                Text("⏪ Undo = dispatch inverse action (delete → create)")
                Text("⏩ Redo = dispatch original action (create → create)")
                Text("🎯 Actions implement InvertibleActionable protocol")
                Text("📝 Lifecycle middlewares track undo/redo events")
                Text("💾 Full task data stored to enable perfect undo")
            }
            .font(.caption)
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Supporting Views

private struct TaskRow: View {
    let task: TaskExample
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .gray)
            }

            Text(task.title)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title3)
                .bold()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ActionableUndoableExampleView()
    }
}

#Preview("With Tasks") {
    let store = ActionableUndoableStore(
        initialState: TaskState(
            tasks: [
                TaskExample(id: "1", title: "Buy groceries", isCompleted: false),
                TaskExample(id: "2", title: "Walk the dog", isCompleted: true),
                TaskExample(id: "3", title: "Write documentation", isCompleted: false)
            ],
            apiCallLog: [
                "✅ API: Created 'Buy groceries'",
                "✅ API: Created 'Walk the dog'",
                "✓ API: Toggled 'Walk the dog'"
            ]
        ),
        reducer: TaskReducer(),
        middlewares: [TaskAPIMiddleware()],
        historyLimit: 20,
        lifecycleMiddlewares: [UndoRedoLoggerMiddleware()]
    )

    return NavigationStack {
        ActionableUndoableExampleView()
    }
}

// MARK: - Key Takeaways

// 1. ACTIONABLE UNDOABLE STORE PURPOSE:
//   - Dispatches inverse actions through middleware (not state restoration)
//   - Allows middleware to intercept and respond to undo/redo
//   - Perfect for reversing API calls, side effects, etc.
//
// 2. INVERTIBLE ACTIONABLE PROTOCOL:
//   - Actions must implement inverse(currentState:) -> Self?
//   - Return the action that reverses the original action's effects
//   - Return nil if action cannot be undone
//   - Store enough data in actions to enable perfect undo
//
// 3. HOW IT WORKS:
//   - User action: .createTask(id: "1", title: "Buy milk")
//   - Reducer adds task to state
//   - Middleware makes API call to create task
//   - Store records action + inverse action
//   - User clicks Undo
//   - Store dispatches inverse: .deleteTask(task: Task(...))
//   - Reducer removes task from state
//   - Middleware makes API call to delete task
//   - Middleware sees the same action flow!
//
// 4. LIFECYCLE MIDDLEWARES:
//   - Receive UndoRedoLifecycleAction events
//   - .willUndo, .didUndo, .willRedo, .didRedo
//   - Use for logging, analytics, notifications
//   - Separate from main action middleware
//
// 5. INVERSE ACTION STRATEGIES:
//   - CREATE ↔ DELETE: Store full object in delete action
//   - UPDATE: Store old value to restore
//   - TOGGLE: Store old boolean value
//   - BATCH: Store all affected items
//
// 6. API REVERSAL PATTERN:
//   - Middleware processes both original and inverse actions
//   - Same switch statement handles create and delete
//   - API service has symmetrical operations
//   - Undo automatically calls the reverse API
//
// 7. DIFFERENCES FROM UNDOABLE STORE:
//   - UndoableStore: Restores state snapshots (bypasses middleware)
//   - ActionableUndoableStore: Dispatches inverse actions (through middleware)
//   - Use UndoableStore for local-only undo
//   - Use ActionableUndoableStore for undo with side effects
//
// 8. MEMORY CONSIDERATIONS:
//   - Stores actions, not states (usually smaller)
//   - Must store enough data in actions for perfect undo
//   - Use historyLimit to cap memory usage
//   - Example: deleteTask stores full Task object
//
// 9. WHEN TO USE:
//   - Use ActionableUndoableStore when:
//     * Actions trigger API calls or side effects
//     * Need to reverse those side effects on undo
//     * Want middleware to intercept undo/redo
//     * Actions are small compared to full state
//
//   - Use UndoableStore when:
//     * Actions are local only (no API calls)
//     * State snapshots are small
//     * Don't need middleware involvement in undo/redo
//
// 10. BEST PRACTICES:
//   - Design actions to be fully invertible
//   - Store enough context for perfect undo (e.g., old values)
//   - Use descriptive undoDescription strings
//   - Test undo/redo paths thoroughly
//   - Consider using lifecycle middlewares for logging
//   - Handle non-invertible actions gracefully (return nil)
//   - Keep historyLimit reasonable for memory
//
// 11. EXAMPLE FLOW:
//   1. User creates task "Buy milk"
//   2. Reducer adds task to state
//   3. Middleware calls API: POST /tasks
//   4. API log shows: "✅ API: Created 'Buy milk'"
//   5. User clicks Undo
//   6. Lifecycle middleware logs: "⏪ UNDO: About to undo 'Create Task'"
//   7. Store dispatches .deleteTask(task: ...)
//   8. Reducer removes task from state
//   9. Middleware calls API: DELETE /tasks/1
//   10. API log shows: "🗑️ API: Deleted 'Buy milk'"
//   11. Lifecycle middleware logs: "⏪ UNDO: Finished undoing 'Create Task'"
//   12. User clicks Redo
//   13. Store dispatches original .createTask(...) again
//   14. Full cycle repeats!
