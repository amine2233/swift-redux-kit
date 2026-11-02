import Foundation
import ReduxKit
import ReduxKitExtensions
import SwiftUI

// MARK: - Filter Offset Example: Task Manager with Bulk Actions

// This example demonstrates how to use filterOffset to perform batch operations
// on filtered subsets of data. Perfect for scenarios like:
// - Marking all completed tasks as archived
// - Updating all high-priority items
// - Batch editing items that match certain criteria

// MARK: - Task Model

/// A task in the task manager
struct TaskFiltredItem: Hashable, Identifiable {
    let id: String
    var title: String
    var isCompleted: Bool
    var priority: Priority
    var category: String

    enum Priority: String, Hashable, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }
}

// MARK: - State

struct TaskManagerFilterState: Hashable {
    var tasks: [TaskFiltredItem] = [
        TaskFiltredItem(
            id: "1",
            title: "Review pull request",
            isCompleted: false,
            priority: .high,
            category: "Work"
        ),
        TaskFiltredItem(
            id: "2",
            title: "Buy groceries",
            isCompleted: false,
            priority: .medium,
            category: "Personal"
        ),
        TaskFiltredItem(
            id: "3",
            title: "Fix bug in login",
            isCompleted: true,
            priority: .high,
            category: "Work"
        ),
        TaskFiltredItem(
            id: "4",
            title: "Walk the dog",
            isCompleted: false,
            priority: .low,
            category: "Personal"
        ),
        TaskFiltredItem(
            id: "5",
            title: "Prepare presentation",
            isCompleted: false,
            priority: .high,
            category: "Work"
        ),
        TaskFiltredItem(
            id: "6",
            title: "Call dentist",
            isCompleted: true,
            priority: .medium,
            category: "Personal"
        )
    ]
    var selectedCategory: String = "All"
    var bulkActionLog: [String] = []
}

// MARK: - Actions

enum TaskManagerAction: Actionable {
    case toggleTask(id: String)
    case setCategory(String)
    case bulkCompleteByCategory(String, TaskItemAction)
    case bulkCompleteByPriority(TaskFiltredItem.Priority, TaskItemAction)
    case bulkToggleCompleted(TaskItemAction)
    case clearLog
}

enum TaskItemAction: Actionable {
    case toggle
    case complete
    case uncomplete
}

// MARK: - Reducer

struct TaskFiltredItemReducer: Reducer {
    func reduce(oldState: TaskFiltredItem, with action: TaskItemAction) -> TaskFiltredItem {
        var state = oldState
        switch action {
        case .toggle:
            state.isCompleted.toggle()
        case .complete:
            state.isCompleted = true
        case .uncomplete:
            state.isCompleted = false
        }
        return state
    }
}

struct TaskManagerReducer: Reducer {
    let taskReducer = TaskFiltredItemReducer()

    /// Create prisms for different filter scenarios
    /// These prisms extract just the TaskItemAction from the compound actions
    static func categoryPrism(for category: String) -> Prism<TaskManagerAction, TaskItemAction> {
        Prism<TaskManagerAction, TaskItemAction>(
            embed: { TaskManagerAction.bulkCompleteByCategory(category, $0) },
            extract: { action in
                if case let .bulkCompleteByCategory(cat, taskAction) = action, cat == category {
                    return taskAction
                }
                return nil
            }
        )
    }

    static func priorityPrism(for priority: TaskFiltredItem
        .Priority
    ) -> Prism<TaskManagerAction, TaskItemAction> {
        Prism<TaskManagerAction, TaskItemAction>(
            embed: { TaskManagerAction.bulkCompleteByPriority(priority, $0) },
            extract: { action in
                if case let .bulkCompleteByPriority(pri, taskAction) = action, pri == priority {
                    return taskAction
                }
                return nil
            }
        )
    }

    static let completedPrism = Prism<TaskManagerAction, TaskItemAction>(
        embed: { TaskManagerAction.bulkToggleCompleted($0) },
        extract: { action in
            if case let .bulkToggleCompleted(taskAction) = action {
                return taskAction
            }
            return nil
        }
    )

    func reduce(oldState: TaskManagerFilterState, with action: TaskManagerAction) -> TaskManagerFilterState {
        var state = oldState

        switch action {
        case let .toggleTask(id):
            if let index = state.tasks.firstIndex(where: { $0.id == id }) {
                state.tasks[index].isCompleted.toggle()
            }

        case let .setCategory(category):
            state.selectedCategory = category

        case let .bulkCompleteByCategory(category, taskAction):
            // Use filterOffset to update only tasks in the selected category
            let categoryReducer = taskReducer.filterOffset(
                keyPath: \TaskManagerFilterState.tasks,
                prism: Self.categoryPrism(for: category),
                predicate: { task in
                    task.category == category
                }
            )
            state = categoryReducer.reduce(
                oldState: state,
                with: .bulkCompleteByCategory(category, taskAction)
            )
            let actionDesc = taskAction == .complete ? "completed" : "uncompleted"
            state.bulkActionLog.append("Bulk \(actionDesc) all tasks in '\(category)'")

        case let .bulkCompleteByPriority(priority, taskAction):
            // Use filterOffset to update only tasks with the selected priority
            let priorityReducer = taskReducer.filterOffset(
                keyPath: \TaskManagerFilterState.tasks,
                prism: Self.priorityPrism(for: priority),
                predicate: { task in
                    task.priority == priority
                }
            )
            state = priorityReducer.reduce(
                oldState: state,
                with: .bulkCompleteByPriority(priority, taskAction)
            )
            let actionDesc = taskAction == .complete ? "completed" : "uncompleted"
            state.bulkActionLog.append("Bulk \(actionDesc) all \(priority.rawValue) priority tasks")

        case let .bulkToggleCompleted(taskAction):
            // Use filterOffset to update only completed tasks
            let completedReducer = taskReducer.filterOffset(
                keyPath: \TaskManagerFilterState.tasks,
                prism: Self.completedPrism,
                predicate: { task in
                    task.isCompleted
                }
            )
            state = completedReducer.reduce(
                oldState: state,
                with: .bulkToggleCompleted(taskAction)
            )
            state.bulkActionLog.append("Toggled all completed tasks")

        case .clearLog:
            state.bulkActionLog.removeAll()
        }

        return state
    }
}

// MARK: - View

struct FilterOffsetExampleView: View {
    @State private var store = Store(
        initialState: TaskManagerFilterState(),
        reducer: TaskManagerReducer(),
        middlewares: []
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                Divider()

                // Bulk Actions
                bulkActionsSection

                Divider()

                // Task List
                taskListSection

                Divider()

                // Action Log
                actionLogSection
            }
            .padding()
        }
        .navigationTitle("Filter Offset Example")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text("FilterOffset Reducer")
                .font(.title2)
                .fontWeight(.bold)

            Text("Batch operations on filtered data")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var bulkActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bulk Actions")
                .font(.headline)

            // Category-based actions
            VStack(alignment: .leading, spacing: 8) {
                Text("By Category")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        store.dispatch(.bulkCompleteByCategory("Work", .complete))
                    } label: {
                        Label("Complete Work", systemImage: "briefcase.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    Button {
                        store.dispatch(.bulkCompleteByCategory("Personal", .complete))
                    } label: {
                        Label("Complete Personal", systemImage: "person.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
            }

            // Priority-based actions
            VStack(alignment: .leading, spacing: 8) {
                Text("By Priority")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(TaskFiltredItem.Priority.allCases, id: \.self) { priority in
                        Button {
                            store.dispatch(.bulkCompleteByPriority(priority, .complete))
                        } label: {
                            Text(priority.rawValue)
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(priorityColor(priority))
                    }
                }
            }

            // Completed tasks action
            VStack(alignment: .leading, spacing: 8) {
                Text("Completed Tasks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    store.dispatch(.bulkToggleCompleted(.uncomplete))
                } label: {
                    Label("Uncomplete All", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var taskListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks (\(store.tasks.count))")
                .font(.headline)

            ForEach(store.tasks) { task in
                TaskRow(task: task) {
                    store.dispatch(.toggleTask(id: task.id))
                }
            }
        }
    }

    private var actionLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Action Log")
                    .font(.headline)

                Spacer()

                if !store.bulkActionLog.isEmpty {
                    Button {
                        store.dispatch(.clearLog)
                    } label: {
                        Text("Clear")
                            .font(.caption)
                    }
                }
            }

            if store.bulkActionLog.isEmpty {
                Text("No actions yet. Try using bulk actions above!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.bulkActionLog.reversed(), id: \.self) { log in
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(log)
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func priorityColor(_ priority: TaskFiltredItem.Priority) -> Color {
        switch priority {
        case .low: .gray
        case .medium: .orange
        case .high: .red
        }
    }
}

// MARK: - Supporting Views

private struct TaskRow: View {
    let task: TaskFiltredItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    Label(task.category, systemImage: categoryIcon(task.category))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(task.priority.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(priorityColor(task.priority).opacity(0.2))
                        .foregroundStyle(priorityColor(task.priority))
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func categoryIcon(_ category: String) -> String {
        category == "Work" ? "briefcase" : "person"
    }

    private func priorityColor(_ priority: TaskFiltredItem.Priority) -> Color {
        switch priority {
        case .low: .gray
        case .medium: .orange
        case .high: .red
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FilterOffsetExampleView()
    }
}
