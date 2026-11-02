import Collections
import Testing
@testable import ReduxKit
@testable import ReduxKitExtensions

@MainActor
struct TreeDictionaryReducerTests {
    struct TodoItem: Hashable, Identifiable {
        var id: Int
        var title: String
        var isCompleted: Bool
    }

    struct TreeKeyedState: Hashable {
        var todos: TreeDictionary<Int, TodoItem>
    }

    enum TodoAction: Actionable {
        case toggle
        case setTitle(String)
    }

    enum TreeKeyedAction: Actionable {
        case updateTodo(Int, TodoAction)

        static let prism = Prism<Self, (Int, TodoAction)>(
            embed: { .updateTodo($0, $1) },
            extract: { action in
                if case let .updateTodo(id, todoAction) = action {
                    return (id, todoAction)
                }
                return nil
            }
        )
    }

    struct TodoReducer: Reducer {
        func reduce(oldState: TodoItem, with action: TodoAction) -> TodoItem {
            var state = oldState
            switch action {
            case .toggle:
                state.isCompleted.toggle()
            case let .setTitle(title):
                state.title = title
            }
            return state
        }
    }

    @Test
    func treeKeyedBasicOperations() {
        let todoReducer = TodoReducer().treeKeyed(
            keyPath: \TreeKeyedState.todos,
            prism: TreeKeyedAction.prism
        )

        var state = TreeKeyedState(
            todos: TreeDictionary([
                TodoItem(id: 1, title: "Task 1", isCompleted: false),
                TodoItem(id: 2, title: "Task 2", isCompleted: false),
                TodoItem(id: 3, title: "Task 3", isCompleted: true)
            ])
        )

        // Toggle todo 1
        state = todoReducer.reduce(
            oldState: state,
            with: .updateTodo(1, .toggle)
        )

        #expect(state.todos[1]?.isCompleted == true)
        #expect(state.todos[2]?.isCompleted == false)
        #expect(state.todos[3]?.isCompleted == true)

        // Update title of todo 2
        state = todoReducer.reduce(
            oldState: state,
            with: .updateTodo(2, .setTitle("Updated Task 2"))
        )

        #expect(state.todos[2]?.title == "Updated Task 2")
        #expect(state.todos[1]?.title == "Task 1") // Unchanged
        #expect(state.todos[3]?.title == "Task 3") // Unchanged
    }

    @Test
    func treeKeyedUpdatesCorrectElement() {
        let todoReducer = TodoReducer().treeKeyed(
            keyPath: \TreeKeyedState.todos,
            prism: TreeKeyedAction.prism
        )

        let state = TreeKeyedState(
            todos: TreeDictionary([
                TodoItem(id: 3, title: "Third", isCompleted: false),
                TodoItem(id: 1, title: "First", isCompleted: false),
                TodoItem(id: 2, title: "Second", isCompleted: false)
            ])
        )

        // Update id 2
        let newState = todoReducer.reduce(
            oldState: state,
            with: .updateTodo(2, .toggle)
        )

        // Verify the correct element was updated via key-based access
        #expect(newState.todos[1]?.isCompleted == false)
        #expect(newState.todos[2]?.isCompleted == true) // Updated
        #expect(newState.todos[3]?.isCompleted == false)

        // Verify we still have all 3 elements
        #expect(newState.todos.count == 3)
    }

    @Test
    func treeKeyedInvalidKey() {
        let todoReducer = TodoReducer().treeKeyed(
            keyPath: \TreeKeyedState.todos,
            prism: TreeKeyedAction.prism
        )

        let state = TreeKeyedState(
            todos: TreeDictionary([
                TodoItem(id: 1, title: "Task 1", isCompleted: false),
                TodoItem(id: 2, title: "Task 2", isCompleted: false)
            ])
        )

        // Try to update non-existent todo
        let newState = todoReducer.reduce(
            oldState: state,
            with: .updateTodo(99, .toggle)
        )

        // State should be unchanged
        #expect(newState == state)
    }

    @Test
    func treeKeyedMultipleUpdates() {
        let todoReducer = TodoReducer().treeKeyed(
            keyPath: \TreeKeyedState.todos,
            prism: TreeKeyedAction.prism
        )

        var state = TreeKeyedState(
            todos: TreeDictionary([
                TodoItem(id: 3, title: "Task 3", isCompleted: false),
                TodoItem(id: 1, title: "Task 1", isCompleted: false),
                TodoItem(id: 2, title: "Task 2", isCompleted: false)
            ])
        )

        // Multiple sequential updates
        state = todoReducer.reduce(oldState: state, with: .updateTodo(1, .toggle))
        state = todoReducer.reduce(oldState: state, with: .updateTodo(2, .toggle))
        state = todoReducer.reduce(oldState: state, with: .updateTodo(3, .toggle))

        // All should be completed - verify via key-based access
        #expect(state.todos[1]?.isCompleted == true)
        #expect(state.todos[2]?.isCompleted == true)
        #expect(state.todos[3]?.isCompleted == true)

        // All 3 elements should still be present
        #expect(state.todos.count == 3)
    }

    @Test
    func treeKeyedWithEmptyCollection() {
        let todoReducer = TodoReducer().treeKeyed(
            keyPath: \TreeKeyedState.todos,
            prism: TreeKeyedAction.prism
        )

        let state = TreeKeyedState(todos: TreeDictionary())

        // Try to update in empty collection
        let newState = todoReducer.reduce(
            oldState: state,
            with: .updateTodo(1, .toggle)
        )

        // State should be unchanged (empty)
        #expect(newState.todos.isEmpty)
    }

    // MARK: - TreeComparableKeyed Tests

    struct Player: Hashable, Identifiable {
        var id: Int
        var name: String
        var score: Int
        var level: Int
        var rank: Int = 0
    }

    struct LeaderboardState: Hashable {
        var players: TreeDictionary<Int, Player>
    }

    enum PlayerAction: Actionable {
        case addPoints(Int)
        case levelUp
    }

    enum LeaderboardAction: Actionable {
        case updatePlayer(Int, PlayerAction)

        static let prism = Prism<Self, (Int, PlayerAction)>(
            embed: { .updatePlayer($0, $1) },
            extract: { action in
                if case let .updatePlayer(id, playerAction) = action {
                    return (id, playerAction)
                }
                return nil
            }
        )
    }

    struct PlayerReducer: Reducer {
        func reduce(oldState: Player, with action: PlayerAction) -> Player {
            var state = oldState
            switch action {
            case let .addPoints(points):
                state.score += points
            case .levelUp:
                state.level += 1
            }
            return state
        }
    }

    @Test
    func treeComparableKeyedSortsByScore() {
        let playerReducer = PlayerReducer().treeComparableKeyed(
            keyPath: \LeaderboardState.players,
            prism: LeaderboardAction.prism,
            comparator: { $0.score > $1.score }, // Sort by descending score
            positionInjector: { player, position in
                var updated = player
                updated.rank = position + 1
                return updated
            }
        )

        var state = LeaderboardState(
            players: TreeDictionary([
                Player(id: 1, name: "Alice", score: 100, level: 5),
                Player(id: 2, name: "Bob", score: 200, level: 8),
                Player(id: 3, name: "Charlie", score: 150, level: 6)
            ])
        )

        // Give Alice 150 points, making her score 250 (highest)
        state = playerReducer.reduce(
            oldState: state,
            with: .updatePlayer(1, .addPoints(150))
        )

        #expect(state.players[1]?.score == 250)
        #expect(state.players[2]?.score == 200)
        #expect(state.players[3]?.score == 150)

        // Verify ranks are injected correctly: Alice (rank 1), Bob (rank 2), Charlie (rank 3)
        #expect(state.players[1]?.rank == 1)
        #expect(state.players[2]?.rank == 2)
        #expect(state.players[3]?.rank == 3)
    }

    @Test
    func treeComparableKeyedMultipleUpdates() {
        let playerReducer = PlayerReducer().treeComparableKeyed(
            keyPath: \LeaderboardState.players,
            prism: LeaderboardAction.prism,
            comparator: { $0.score > $1.score },
            positionInjector: { player, position in
                var updated = player
                updated.rank = position + 1
                return updated
            }
        )

        var state = LeaderboardState(
            players: TreeDictionary([
                Player(id: 1, name: "Alice", score: 100, level: 5),
                Player(id: 2, name: "Bob", score: 100, level: 5),
                Player(id: 3, name: "Charlie", score: 100, level: 5)
            ])
        )

        // Give different scores to each player
        state = playerReducer.reduce(oldState: state, with: .updatePlayer(1, .addPoints(50)))
        state = playerReducer.reduce(oldState: state, with: .updatePlayer(2, .addPoints(200)))
        state = playerReducer.reduce(oldState: state, with: .updatePlayer(3, .addPoints(100)))

        #expect(state.players[1]?.score == 150)
        #expect(state.players[2]?.score == 300)
        #expect(state.players[3]?.score == 200)

        // Verify ranks: Bob (rank 1), Charlie (rank 2), Alice (rank 3)
        #expect(state.players[1]?.rank == 3)
        #expect(state.players[2]?.rank == 1)
        #expect(state.players[3]?.rank == 2)
    }

    @Test
    func treeComparableKeyedComplexComparator() {
        // Sort by level (descending), then by score (descending)
        let playerReducer = PlayerReducer().treeComparableKeyed(
            keyPath: \LeaderboardState.players,
            prism: LeaderboardAction.prism,
            comparator: { lhs, rhs in
                if lhs.level != rhs.level {
                    return lhs.level > rhs.level
                }
                return lhs.score > rhs.score
            },
            positionInjector: { player, position in
                var updated = player
                updated.rank = position + 1
                return updated
            }
        )

        var state = LeaderboardState(
            players: TreeDictionary([
                Player(id: 1, name: "Alice", score: 100, level: 5),
                Player(id: 2, name: "Bob", score: 200, level: 5),
                Player(id: 3, name: "Charlie", score: 150, level: 6)
            ])
        )

        // Level up Alice to level 6
        state = playerReducer.reduce(
            oldState: state,
            with: .updatePlayer(1, .levelUp)
        )

        #expect(state.players[1]?.level == 6)

        // Verify ranks by level then score:
        // Charlie (L6, 150, rank 1), Alice (L6, 100, rank 2), Bob (L5, 200, rank 3)
        #expect(state.players[1]?.rank == 2) // Alice: L6, 100
        #expect(state.players[2]?.rank == 3) // Bob: L5, 200
        #expect(state.players[3]?.rank == 1) // Charlie: L6, 150
    }

    @Test
    func treeComparableKeyedInvalidKey() {
        let playerReducer = PlayerReducer().treeComparableKeyed(
            keyPath: \LeaderboardState.players,
            prism: LeaderboardAction.prism,
            comparator: { $0.score > $1.score },
            positionInjector: { player, position in
                var updated = player
                updated.rank = position + 1
                return updated
            }
        )

        let state = LeaderboardState(
            players: TreeDictionary([
                Player(id: 1, name: "Alice", score: 100, level: 5),
                Player(id: 2, name: "Bob", score: 200, level: 8)
            ])
        )

        // Try to update non-existent player
        let newState = playerReducer.reduce(
            oldState: state,
            with: .updatePlayer(99, .addPoints(100))
        )

        // State should be unchanged
        #expect(newState == state)
    }

    @Test
    func treeComparableKeyedEmptyCollection() {
        let playerReducer = PlayerReducer().treeComparableKeyed(
            keyPath: \LeaderboardState.players,
            prism: LeaderboardAction.prism,
            comparator: { $0.score > $1.score },
            positionInjector: { player, position in
                var updated = player
                updated.rank = position + 1
                return updated
            }
        )

        let state = LeaderboardState(players: TreeDictionary())

        // Try to update in empty collection
        let newState = playerReducer.reduce(
            oldState: state,
            with: .updatePlayer(1, .addPoints(100))
        )

        // State should remain empty
        #expect(newState.players.isEmpty)
    }

    // MARK: - TreeFilterKeyed Tests

    struct Task: Hashable, Identifiable {
        var id: Int
        var title: String
        var isCompleted: Bool
        var priority: Int
    }

    struct TaskListState: Hashable {
        var tasks: TreeDictionary<Int, Task>
    }

    enum TaskAction: Actionable {
        case complete
        case increasePriority
    }

    enum TaskListAction: Actionable {
        case bulkComplete(TaskAction)
        case bulkIncreasePriority(TaskAction)

        static let completePrism = Prism<Self, TaskAction>(
            embed: { .bulkComplete($0) },
            extract: { action in
                if case let .bulkComplete(taskAction) = action {
                    return taskAction
                }
                return nil
            }
        )

        static let priorityPrism = Prism<Self, TaskAction>(
            embed: { .bulkIncreasePriority($0) },
            extract: { action in
                if case let .bulkIncreasePriority(taskAction) = action {
                    return taskAction
                }
                return nil
            }
        )
    }

    struct TaskReducer: Reducer {
        func reduce(oldState: Task, with action: TaskAction) -> Task {
            var state = oldState
            switch action {
            case .complete:
                state.isCompleted = true
            case .increasePriority:
                state.priority += 1
            }
            return state
        }
    }

    @Test
    func treeFilterKeyedBasicOperation() {
        let taskReducer = TaskReducer().treeFilterKeyed(
            keyPath: \TaskListState.tasks,
            prism: TaskListAction.completePrism,
            predicate: { !$0.isCompleted } // Only incomplete tasks
        )

        var state = TaskListState(
            tasks: TreeDictionary([
                Task(id: 1, title: "Task 1", isCompleted: false, priority: 1),
                Task(id: 2, title: "Task 2", isCompleted: true, priority: 2),
                Task(id: 3, title: "Task 3", isCompleted: false, priority: 3)
            ])
        )

        // Bulk complete all incomplete tasks
        state = taskReducer.reduce(
            oldState: state,
            with: .bulkComplete(.complete)
        )

        // Tasks 1 and 3 should be completed, task 2 unchanged
        #expect(state.tasks[1]?.isCompleted == true)
        #expect(state.tasks[2]?.isCompleted == true) // Was already completed
        #expect(state.tasks[3]?.isCompleted == true)
    }

    @Test
    func treeFilterKeyedMultipleBulkOperations() {
        let completeReducer = TaskReducer().treeFilterKeyed(
            keyPath: \TaskListState.tasks,
            prism: TaskListAction.completePrism,
            predicate: { !$0.isCompleted }
        )

        let priorityReducer = TaskReducer().treeFilterKeyed(
            keyPath: \TaskListState.tasks,
            prism: TaskListAction.priorityPrism,
            predicate: { $0.priority < 5 }
        )

        var state = TaskListState(
            tasks: TreeDictionary([
                Task(id: 1, title: "Task 1", isCompleted: false, priority: 1),
                Task(id: 2, title: "Task 2", isCompleted: false, priority: 3),
                Task(id: 3, title: "Task 3", isCompleted: false, priority: 6)
            ])
        )

        // Increase priority for tasks with priority < 5
        state = priorityReducer.reduce(
            oldState: state,
            with: .bulkIncreasePriority(.increasePriority)
        )

        #expect(state.tasks[1]?.priority == 2)
        #expect(state.tasks[2]?.priority == 4)
        #expect(state.tasks[3]?.priority == 6) // Unchanged (was already 6)

        // Complete all incomplete tasks
        state = completeReducer.reduce(
            oldState: state,
            with: .bulkComplete(.complete)
        )

        #expect(state.tasks[1]?.isCompleted == true)
        #expect(state.tasks[2]?.isCompleted == true)
        #expect(state.tasks[3]?.isCompleted == true)
    }

    @Test
    func treeFilterKeyedNoMatches() {
        let taskReducer = TaskReducer().treeFilterKeyed(
            keyPath: \TaskListState.tasks,
            prism: TaskListAction.completePrism,
            predicate: { !$0.isCompleted }
        )

        let state = TaskListState(
            tasks: TreeDictionary([
                Task(id: 1, title: "Task 1", isCompleted: true, priority: 1),
                Task(id: 2, title: "Task 2", isCompleted: true, priority: 2)
            ])
        )

        // Try to complete already completed tasks
        let newState = taskReducer.reduce(
            oldState: state,
            with: .bulkComplete(.complete)
        )

        // State should be unchanged since no tasks matched the predicate
        #expect(newState == state)
    }

    @Test
    func treeFilterKeyedEmptyCollection() {
        let taskReducer = TaskReducer().treeFilterKeyed(
            keyPath: \TaskListState.tasks,
            prism: TaskListAction.completePrism,
            predicate: { !$0.isCompleted }
        )

        let state = TaskListState(tasks: TreeDictionary())

        // Try to operate on empty collection
        let newState = taskReducer.reduce(
            oldState: state,
            with: .bulkComplete(.complete)
        )

        // State should remain empty
        #expect(newState.tasks.isEmpty)
    }

    @Test
    func treeFilterKeyedPartialMatches() {
        let taskReducer = TaskReducer().treeFilterKeyed(
            keyPath: \TaskListState.tasks,
            prism: TaskListAction.priorityPrism,
            predicate: { $0.priority >= 2 && $0.priority <= 4 }
        )

        var state = TaskListState(
            tasks: TreeDictionary([
                Task(id: 1, title: "Task 1", isCompleted: false, priority: 1),
                Task(id: 2, title: "Task 2", isCompleted: false, priority: 2),
                Task(id: 3, title: "Task 3", isCompleted: false, priority: 3),
                Task(id: 4, title: "Task 4", isCompleted: false, priority: 4),
                Task(id: 5, title: "Task 5", isCompleted: false, priority: 5)
            ])
        )

        // Increase priority for tasks with priority 2-4
        state = taskReducer.reduce(
            oldState: state,
            with: .bulkIncreasePriority(.increasePriority)
        )

        // Only tasks 2, 3, and 4 should have increased priority
        #expect(state.tasks[1]?.priority == 1) // Unchanged
        #expect(state.tasks[2]?.priority == 3) // Increased
        #expect(state.tasks[3]?.priority == 4) // Increased
        #expect(state.tasks[4]?.priority == 5) // Increased
        #expect(state.tasks[5]?.priority == 5) // Unchanged
    }
}
