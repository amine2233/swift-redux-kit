import Foundation
import ReduxKit
import ReduxKitExtensions
import SwiftUI

// MARK: - Keyed Reducer Example: Managing Collections

// This example demonstrates how to use .keyed() to manage a collection of items in a dictionary,
// where each item has its own state and reducer.
//
// The problem:
// - You have a collection of items (e.g., todos, users, products)
// - Each item needs its own independent state
// - Each item should be managed by the same child reducer
// - Parent needs to route actions to specific items by ID
//
// The solution:
// - Store items in a Dictionary<ID, ItemState>
// - Use Prism to extract (ID, ItemAction) tuples from parent actions
// - Use .keyed() to lift the child reducer to work on the dictionary
// - The keyed reducer applies child reducer to the item at the given ID

// MARK: - Child Feature: Todo Item

/// Individual todo item state
struct TodoItemState: Sendable, Hashable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var priority: Priority

    enum Priority: String, Sendable, Hashable, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        var color: Color {
            switch self {
            case .low: .green
            case .medium: .orange
            case .high: .red
            }
        }
    }
}

/// Actions for individual todo items
enum TodoItemAction: Actionable {
    case updateTitle(String)
    case toggleCompleted
    case setPriority(TodoItemState.Priority)
}

/// Reducer for a single todo item
struct TodoItemReducer: Reducer {
    func reduce(oldState: TodoItemState, with action: TodoItemAction) -> TodoItemState {
        var state = oldState

        switch action {
        case let .updateTitle(title):
            state.title = title

        case .toggleCompleted:
            state.isCompleted.toggle()

        case let .setPriority(priority):
            state.priority = priority
        }

        return state
    }
}

// MARK: - Parent: Todo List State & Actions

/// Parent state containing all todos in a dictionary
struct TodoListState: Sendable, Hashable {
    var todos: [UUID: TodoItemState] = [:]
    var filter: FilterType = .all

    enum FilterType: String, CaseIterable, Sendable, Hashable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
    }

    var filteredTodos: [TodoItemState] {
        let allTodos = todos.values.sorted { $0.title < $1.title }

        switch filter {
        case .all:
            return allTodos
        case .active:
            return allTodos.filter { !$0.isCompleted }
        case .completed:
            return allTodos.filter { $0.isCompleted }
        }
    }

    var stats: (total: Int, completed: Int, active: Int) {
        let total = todos.count
        let completed = todos.values.filter { $0.isCompleted }.count
        let active = total - completed
        return (total, completed, active)
    }
}

/// Parent actions - includes keyed child actions
enum TodoListAction: Actionable {
    case addTodo(String)
    case deleteTodo(UUID)
    case setFilter(TodoListState.FilterType)
    case clearCompleted
    case todoItem(UUID, TodoItemAction) // Keyed action: (ID, Child Action)
}

// MARK: - Prism for Keyed Actions

extension Prism where Source == TodoListAction, Target == (UUID, TodoItemAction) {
    /// Prism that extracts (ID, TodoItemAction) tuples from TodoListAction
    static var todoItem: Prism<TodoListAction, (UUID, TodoItemAction)> {
        Prism(
            // embed: Wrap (ID, Action) tuple into parent action
            embed: { tuple in
                .todoItem(tuple.0, tuple.1)
            },
            // extract: Extract (ID, Action) tuple from parent action
            extract: { parentAction in
                guard case let .todoItem(id, action) = parentAction else {
                    return nil
                }

                return (id, action)
            }
        )
    }
}

// MARK: - Parent Reducer with Keyed Child

struct TodoListReducer: Reducer {
    func reduce(oldState: TodoListState, with action: TodoListAction) -> TodoListState {
        var state = oldState

        // Handle parent-level actions
        switch action {
        case let .addTodo(title):
            let newTodo = TodoItemState(
                id: UUID(),
                title: title,
                isCompleted: false,
                priority: .medium
            )
            state.todos[newTodo.id] = newTodo

        case let .deleteTodo(id):
            state.todos.removeValue(forKey: id)

        case let .setFilter(filter):
            state.filter = filter

        case .clearCompleted:
            state.todos = state.todos.filter { !$0.value.isCompleted }

        case .todoItem:
            // Don't handle here - let the keyed reducer handle it
            break
        }

        // Apply the keyed child reducer using Prism
        // It will only modify the todo item at the specified ID
        let keyedReducer = TodoItemReducer().keyed(
            keyPath: \TodoListState.todos, // Where the dictionary lives
            prism: .todoItem // How to extract (ID, Action) tuples
        )
        state = keyedReducer.reduce(oldState: state, with: action)

        return state
    }
}

// MARK: - SwiftUI Example View

struct KeyedExampleView: View {
    @Environment(Store<TodoListState, TodoListAction>.self) private var store
    @State private var newTodoTitle: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Statistics
                statsSection

                Divider()

                // Add Todo
                addTodoSection

                Divider()

                // Filter
                filterSection

                // Todo List
                todoListSection

                // Clear Completed
                if store.stats.completed > 0 {
                    clearCompletedButton
                }

                // Explanation
                explanationSection
            }
            .padding()
        }
        .navigationTitle("Keyed Example: Todos")
    }

    // MARK: - Sections

    private var statsSection: some View {
        HStack(spacing: 20) {
            StatBadge(label: "Total", value: store.stats.total, color: .blue)
            StatBadge(label: "Active", value: store.stats.active, color: .orange)
            StatBadge(label: "Done", value: store.stats.completed, color: .green)
        }
    }

    private var addTodoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add New Todo")
                .font(.headline)

            HStack {
                TextField("Enter todo title", text: $newTodoTitle)
                    .textFieldStyle(.roundedBorder)

                Button {
                    guard !newTodoTitle.isEmpty else { return }

                    store.dispatch(.addTodo(newTodoTitle))
                    newTodoTitle = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filter")
                .font(.headline)

            Picker("Filter", selection: Binding(
                get: { store.filter },
                set: { store.dispatch(.setFilter($0)) }
            )) {
                ForEach(TodoListState.FilterType.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var todoListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Todos (\(store.filteredTodos.count))")
                .font(.headline)

            if store.filteredTodos.isEmpty {
                Text("No todos to show")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                ForEach(store.filteredTodos, id: \.id) { todo in
                    TodoItemRow(todo: todo)
                }
            }
        }
    }

    private var clearCompletedButton: some View {
        Button {
            store.dispatch(.clearCompleted)
        } label: {
            Text("Clear Completed (\(store.stats.completed))")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How .keyed() Works:")
                .font(.headline)

            Group {
                Text("• Todos stored in Dictionary<UUID, TodoItemState>")
                Text("• Each todo managed by TodoItemReducer")
                Text("• Actions: .todoItem(id, .toggleCompleted)")
                Text("• Prism extracts (ID, Action) tuple")
                Text("• .keyed() applies reducer to item at ID")
                Text("• Parent handles add/delete/filter")
            }
            .font(.caption)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Supporting Views

private struct StatBadge: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2)
                .bold()
                .foregroundStyle(color)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TodoItemRow: View {
    @Environment(Store<TodoListState, TodoListAction>.self) private var store
    let todo: TodoItemState
    @State private var isEditingTitle: Bool = false
    @State private var editedTitle: String = ""

    var body: some View {
        HStack(spacing: 12) {
            // Completion toggle
            Button {
                store.dispatch(.todoItem(todo.id, .toggleCompleted))
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isCompleted ? .green : .gray)
            }

            // Title
            if isEditingTitle {
                TextField("Title", text: $editedTitle, onCommit: {
                    store.dispatch(.todoItem(todo.id, .updateTitle(editedTitle)))
                    isEditingTitle = false
                })
                .textFieldStyle(.roundedBorder)
            } else {
                Text(todo.title)
                    .strikethrough(todo.isCompleted)
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    .onTapGesture {
                        editedTitle = todo.title
                        isEditingTitle = true
                    }
            }

            Spacer()

            // Priority picker
            Menu {
                ForEach(TodoItemState.Priority.allCases, id: \.self) { priority in
                    Button {
                        store.dispatch(.todoItem(todo.id, .setPriority(priority)))
                    } label: {
                        HStack {
                            Text(priority.rawValue)
                            if todo.priority == priority {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(todo.priority.color)
                        .frame(width: 8, height: 8)
                    Text(todo.priority.rawValue)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(todo.priority.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Delete button
            Button {
                store.dispatch(.deleteTodo(todo.id))
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

#Preview {
    let initialState = TodoListState(
        todos: [
            UUID(1): TodoItemState(id: UUID(1), title: "Learn ReduxKit", isCompleted: true, priority: .high),
            UUID(2): TodoItemState(
                id: UUID(2),
                title: "Build sample app",
                isCompleted: false,
                priority: .medium
            ),
            UUID(3): TodoItemState(
                id: UUID(3),
                title: "Write documentation",
                isCompleted: false,
                priority: .low
            )
        ]
    )

    let store = Store(
        initialState: initialState,
        reducer: TodoListReducer(),
        middlewares: []
    )

    return NavigationStack {
        KeyedExampleView()
            .environment(store)
    }
}

// MARK: - Key Takeaways

// 1. KEYED REDUCER PURPOSE:
//   - Manages collections of items stored in Dictionary<Key, ItemState>
//   - Routes actions to specific items by their key/ID
//   - Applies child reducer to individual items
//
// 2. KEYED STRUCTURE:
//   - Parent state contains Dictionary<ID, ChildState>
//   - Parent actions include .childAction(ID, ChildAction)
//   - Prism extracts (ID, ChildAction) tuples
//
// 3. KEYED USAGE:
//   - `.keyed(keyPath:prism:)` creates a reducer that:
//     * Works on parent state containing a dictionary
//     * Extracts (Key, Action) from parent action using prism
//     * Applies child reducer to dictionary[key]
//     * Returns updated parent state
//
// 4. BENEFITS:
//   - Each item independently managed by same reducer
//   - Type-safe routing of actions by ID
//   - Clean separation: parent handles collection, child handles item
//   - Easy to add/remove items without changing reducer logic
//
// 5. COMMON USE CASES:
//   - Todo lists (items keyed by ID)
//   - User management (users keyed by userID)
//   - Shopping cart (products keyed by productID)
//   - Chat messages (messages keyed by messageID)
//
// 6. EXAMPLE FLOW:
//   User clicks toggle on todo with id=123
//   → Dispatches: .todoItem(123, .toggleCompleted)
//   → Parent reducer sees action
//   → Keyed reducer's prism extracts (123, .toggleCompleted)
//   → TodoItemReducer toggles todos[123].isCompleted
//   → State updates, UI re-renders
//
// 7. COMPARISON WITH .lifted():
//   - .lifted(): One child state at a keyPath (e.g., state.profile)
//   - .keyed(): Multiple child states in dictionary (e.g., state.todos[id])
//   - Both use Prism for action routing
