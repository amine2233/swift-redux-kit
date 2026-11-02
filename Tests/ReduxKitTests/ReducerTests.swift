import Testing
@testable import ReduxKit

struct ReducerTests {
    struct State: Hashable {
        var counter: Int
    }

    enum Action: Actionable {
        case increment
        case decrement
    }

    struct CounterReducer: Reducer {
        func reduce(oldState: State, with action: Action) -> State {
            var state = oldState

            switch action {
            case .increment: state.counter += 1
            case .decrement: state.counter -= 1
            }

            return state
        }
    }

    @Test
    func optional() {
        var state: State? = State(counter: 10)
        let reducer = CounterReducer()
        let optionalReducer = reducer.optional()
        let newState = optionalReducer.reduce(oldState: state, with: .increment)
        #expect(newState == State(counter: 11))

        state = nil
        let anotherNewState = optionalReducer.reduce(oldState: state, with: .decrement)
        #expect(anotherNewState == nil)
    }

    @Test
    func offset() {
        struct OffsetState: Hashable {
            var value: [State] = [.init(counter: 1), .init(counter: 2)]
        }

        enum OffsetAction: Actionable {
            case action(Int, Action)

            static var prism: Prism<OffsetAction, (Int, Action)> {
                .init(embed: OffsetAction.action) {
                    guard case let OffsetAction.action(offset, action) = $0 else {
                        return nil
                    }

                    return (offset, action)
                }
            }
        }

        let offsetReducer = CounterReducer().offset(
            keyPath: \OffsetState.value,
            prism: OffsetAction.prism
        )

        var state = OffsetState()

        let newState = offsetReducer.reduce(oldState: state, with: .action(1, .increment))
        state.value[1].counter += 1
        #expect(newState == state)

        let anotherState = offsetReducer.reduce(oldState: state, with: .action(3, .increment))
        #expect(anotherState == state)
    }

    @Test
    func keyed() {
        struct KeyedState: Hashable {
            var value: [String: State] = ["one": .init(counter: 10)]
        }

        enum KeyedAction: Actionable {
            case action(String, Action)

            static var prism: Prism<KeyedAction, (String, Action)> {
                .init(embed: KeyedAction.action) {
                    guard case let KeyedAction.action(key, action) = $0 else {
                        return nil
                    }

                    return (key, action)
                }
            }
        }

        let keyedReducer = CounterReducer().keyed(
            keyPath: \KeyedState.value,
            prism: KeyedAction.prism
        )

        var state = KeyedState()
        let newState = keyedReducer.reduce(oldState: state, with: .action("one", .increment))
        state.value["one"]?.counter += 1
        #expect(newState == state)

        let anotherNewState = keyedReducer.reduce(oldState: state, with: .action("two", .increment))
        #expect(anotherNewState == state)
    }

    @Test
    func combined() {
        let combinedReducer: some Reducer<State, Action> = CombinedReducer(
            reducers: [
                CounterReducer(), CounterReducer()
            ]
        )

        let state = State(counter: 0)
        let newState = combinedReducer.reduce(oldState: state, with: .increment)

        #expect(newState == .init(counter: 2))
    }

    @Test
    func lift() {
        struct LiftedState: Hashable {
            var state: State
        }

        enum LiftedAction: Actionable {
            case action(Action)

            static var prism: Prism<LiftedAction, Action> {
                .init(embed: LiftedAction.action) {
                    guard case let LiftedAction.action(action) = $0 else {
                        return nil
                    }

                    return action
                }
            }
        }

        let liftedReducer = CounterReducer().lifted(
            keyPath: \LiftedState.state,
            prism: LiftedAction.prism
        )

        var state = LiftedState(state: .init(counter: 1))
        let newState = liftedReducer.reduce(oldState: state, with: .action(.increment))
        state.state.counter += 1
        #expect(newState == state)
    }

    @Test
    func identity() {
        let identityReducer: some Reducer<State, Action> = IdentityReducer()
        let state = State(counter: 1)
        let newState = identityReducer.reduce(oldState: state, with: .increment)
        #expect(state == newState)
    }

    @Test
    func filterOffset() {
        struct Task: Hashable {
            var id: Int
            var counter: Int
            var isCompleted: Bool
        }

        struct TaskState: Hashable {
            var counter: Int
        }

        struct FilterOffsetState: Hashable {
            var tasks: [Task] = [
                Task(id: 1, counter: 0, isCompleted: false),
                Task(id: 2, counter: 0, isCompleted: true),
                Task(id: 3, counter: 0, isCompleted: false),
                Task(id: 4, counter: 0, isCompleted: true)
            ]
        }

        enum FilterOffsetAction: Actionable {
            case updateCompleted(Action)
            case updateIncomplete(Action)

            static var completedPrism: Prism<FilterOffsetAction, Action> {
                .init(embed: FilterOffsetAction.updateCompleted) {
                    guard case let .updateCompleted(action) = $0 else {
                        return nil
                    }

                    return action
                }
            }

            static var incompletePrism: Prism<FilterOffsetAction, Action> {
                .init(embed: FilterOffsetAction.updateIncomplete) {
                    guard case let .updateIncomplete(action) = $0 else {
                        return nil
                    }

                    return action
                }
            }
        }

        // Reducer that operates on Task by updating its counter
        struct TaskReducer: Reducer {
            func reduce(oldState: Task, with action: Action) -> Task {
                var state = oldState
                switch action {
                case .increment: state.counter += 1
                case .decrement: state.counter -= 1
                }
                return state
            }
        }

        // Filter reducer that only updates completed tasks
        let completedTasksReducer = TaskReducer().filterOffset(
            keyPath: \FilterOffsetState.tasks,
            prism: FilterOffsetAction.completedPrism,
            predicate: { $0.isCompleted }
        )

        // Filter reducer that only updates incomplete tasks
        let incompleteTasksReducer = TaskReducer().filterOffset(
            keyPath: \FilterOffsetState.tasks,
            prism: FilterOffsetAction.incompletePrism,
            predicate: { !$0.isCompleted }
        )

        var state = FilterOffsetState()

        // Increment completed tasks
        let newState = completedTasksReducer.reduce(
            oldState: state,
            with: .updateCompleted(.increment)
        )

        // Only completed tasks (id 2 and 4) should be updated
        #expect(newState.tasks[0].counter == 0) // id 1, incomplete
        #expect(newState.tasks[1].counter == 1) // id 2, completed
        #expect(newState.tasks[2].counter == 0) // id 3, incomplete
        #expect(newState.tasks[3].counter == 1) // id 4, completed

        // Decrement incomplete tasks
        state = newState
        let anotherState = incompleteTasksReducer.reduce(
            oldState: state,
            with: .updateIncomplete(.decrement)
        )

        // Only incomplete tasks (id 1 and 3) should be updated
        #expect(anotherState.tasks[0].counter == -1) // id 1, incomplete
        #expect(anotherState.tasks[1].counter == 1) // id 2, completed (unchanged)
        #expect(anotherState.tasks[2].counter == -1) // id 3, incomplete
        #expect(anotherState.tasks[3].counter == 1) // id 4, completed (unchanged)

        // Test with action that doesn't match prism
        let unchangedState = completedTasksReducer.reduce(
            oldState: state,
            with: .updateIncomplete(.increment)
        )
        #expect(unchangedState == state)

        // Test that no changes occur when no items match predicate
        let stateWithNoCompleted = FilterOffsetState(
            tasks: [
                Task(id: 1, counter: 0, isCompleted: false),
                Task(id: 2, counter: 0, isCompleted: false)
            ]
        )
        let unchangedResult = completedTasksReducer.reduce(
            oldState: stateWithNoCompleted,
            with: .updateCompleted(.increment)
        )
        // State should be unchanged when no items match the predicate
        #expect(unchangedResult == stateWithNoCompleted)
        #expect(unchangedResult.tasks[0].counter == 0)
        #expect(unchangedResult.tasks[1].counter == 0)
    }

    @Test
    func filteredKeyed() {
        // Test filtering dictionary values based on a predicate
        struct TodoItem: Hashable {
            var id: Int
            var title: String
            var isCompleted: Bool
            var priority: Int
        }

        struct FilteredKeyedState: Hashable {
            var todos: [Int: TodoItem]
        }

        enum TodoItemAction: Actionable {
            case toggleComplete
            case increasePriority
            case decreasePriority
        }

        enum FilteredKeyedAction: Actionable {
            case updateCompleted(TodoItemAction)
            case updateHighPriority(TodoItemAction)

            static let completedPrism = Prism<Self, TodoItemAction>(
                embed: { .updateCompleted($0) },
                extract: { action in
                    if case let .updateCompleted(itemAction) = action {
                        return itemAction
                    }
                    return nil
                }
            )

            static let highPriorityPrism = Prism<Self, TodoItemAction>(
                embed: { .updateHighPriority($0) },
                extract: { action in
                    if case let .updateHighPriority(itemAction) = action {
                        return itemAction
                    }
                    return nil
                }
            )
        }

        struct TodoItemReducer: Reducer {
            func reduce(oldState: TodoItem, with action: TodoItemAction) -> TodoItem {
                var state = oldState
                switch action {
                case .toggleComplete:
                    state.isCompleted.toggle()
                case .increasePriority:
                    state.priority += 1
                case .decreasePriority:
                    state.priority -= 1
                }
                return state
            }
        }

        // Filter reducer that only updates completed todos
        let completedTodosReducer = TodoItemReducer().filteredKeyed(
            keyPath: \FilteredKeyedState.todos,
            prism: FilteredKeyedAction.completedPrism,
            predicate: { $0.isCompleted }
        )

        // Filter reducer that only updates high priority todos (priority >= 5)
        let highPriorityTodosReducer = TodoItemReducer().filteredKeyed(
            keyPath: \FilteredKeyedState.todos,
            prism: FilteredKeyedAction.highPriorityPrism,
            predicate: { $0.priority >= 5 }
        )

        var state = FilteredKeyedState(
            todos: [
                1: TodoItem(id: 1, title: "Task 1", isCompleted: false, priority: 3),
                2: TodoItem(id: 2, title: "Task 2", isCompleted: true, priority: 5),
                3: TodoItem(id: 3, title: "Task 3", isCompleted: false, priority: 7),
                4: TodoItem(id: 4, title: "Task 4", isCompleted: true, priority: 2)
            ]
        )

        // Toggle completed todos
        let newState = completedTodosReducer.reduce(
            oldState: state,
            with: .updateCompleted(.toggleComplete)
        )

        // Only completed todos (id 2 and 4) should be toggled
        #expect(newState.todos[1]?.isCompleted == false) // unchanged
        #expect(newState.todos[2]?.isCompleted == false) // toggled
        #expect(newState.todos[3]?.isCompleted == false) // unchanged
        #expect(newState.todos[4]?.isCompleted == false) // toggled

        // Increase priority of high priority todos
        state = newState
        let anotherState = highPriorityTodosReducer.reduce(
            oldState: state,
            with: .updateHighPriority(.increasePriority)
        )

        // Only high priority todos (id 2 with priority 5 and id 3 with priority 7) should be updated
        #expect(anotherState.todos[1]?.priority == 3) // unchanged
        #expect(anotherState.todos[2]?.priority == 6) // increased
        #expect(anotherState.todos[3]?.priority == 8) // increased
        #expect(anotherState.todos[4]?.priority == 2) // unchanged

        // Test with action that doesn't match prism
        let unchangedState = completedTodosReducer.reduce(
            oldState: state,
            with: .updateHighPriority(.increasePriority)
        )
        #expect(unchangedState == state)

        // Test with empty dictionary
        let emptyState = FilteredKeyedState(todos: [:])
        let resultState = completedTodosReducer.reduce(
            oldState: emptyState,
            with: .updateCompleted(.toggleComplete)
        )
        #expect(resultState.todos.isEmpty)

        // Test that no changes occur when no items match predicate
        let stateWithNoCompleted = FilteredKeyedState(
            todos: [
                1: TodoItem(id: 1, title: "Task 1", isCompleted: false, priority: 3),
                2: TodoItem(id: 2, title: "Task 2", isCompleted: false, priority: 5)
            ]
        )
        let unchangedResult = completedTodosReducer.reduce(
            oldState: stateWithNoCompleted,
            with: .updateCompleted(.toggleComplete)
        )
        // State should be unchanged when no items match the predicate
        #expect(unchangedResult == stateWithNoCompleted)
        #expect(unchangedResult.todos[1]?.isCompleted == false)
        #expect(unchangedResult.todos[2]?.isCompleted == false)
    }

    @Test
    func sortedOffset() {
        // Test that array remains sorted after updates
        struct TaskItem: Hashable {
            var id: Int
            var title: String
            var priority: Int
        }

        struct SortedOffsetState: Hashable {
            var tasks: [TaskItem]
        }

        enum TaskItemAction: Actionable {
            case increasePriority
            case decreasePriority
            case setPriority(Int)
        }

        enum SortedOffsetAction: Actionable {
            case updateTask(Int, TaskItemAction)

            static let prism = Prism<Self, (Int, TaskItemAction)>(
                embed: { .updateTask($0, $1) },
                extract: { action in
                    if case let .updateTask(index, itemAction) = action {
                        return (index, itemAction)
                    }
                    return nil
                }
            )
        }

        struct TaskItemReducer: Reducer {
            func reduce(oldState: TaskItem, with action: TaskItemAction) -> TaskItem {
                var state = oldState
                switch action {
                case .increasePriority:
                    state.priority += 1
                case .decreasePriority:
                    state.priority -= 1
                case let .setPriority(priority):
                    state.priority = priority
                }
                return state
            }
        }

        // Sort by priority descending (highest priority first)
        let sortedReducer = TaskItemReducer().sortedOffset(
            keyPath: \SortedOffsetState.tasks,
            prism: SortedOffsetAction.prism,
            comparator: { $0.priority > $1.priority }
        )

        var state = SortedOffsetState(
            tasks: [
                TaskItem(id: 1, title: "Task 1", priority: 5),
                TaskItem(id: 2, title: "Task 2", priority: 3),
                TaskItem(id: 3, title: "Task 3", priority: 7)
            ]
        )

        // Initial state should be sorted: [7, 5, 3]
        #expect(state.tasks[0].priority == 5)
        #expect(state.tasks[1].priority == 3)
        #expect(state.tasks[2].priority == 7)

        // Increase priority of task at index 1 (priority 3 -> 4)
        state = sortedReducer.reduce(
            oldState: state,
            with: .updateTask(1, .increasePriority)
        )

        // Array should be re-sorted after update: [7, 5, 4]
        #expect(state.tasks[0].priority == 7) // id 3
        #expect(state.tasks[1].priority == 5) // id 1
        #expect(state.tasks[2].priority == 4) // id 2 (was at index 1, now sorted)

        // Increase priority of task at index 2 (priority 4 -> 5)
        state = sortedReducer.reduce(
            oldState: state,
            with: .updateTask(2, .increasePriority)
        )

        // Array should be re-sorted: [7, 5, 5]
        #expect(state.tasks[0].priority == 7) // id 3
        // ids 1 and 2 both have priority 5, stable sort keeps original order
        #expect(state.tasks[1].priority == 5)
        #expect(state.tasks[2].priority == 5)

        // Set priority of first task to 1 (priority 7 -> 1)
        state = sortedReducer.reduce(
            oldState: state,
            with: .updateTask(0, .setPriority(1))
        )

        // Array should be re-sorted: [5, 5, 1]
        #expect(state.tasks[0].priority == 5)
        #expect(state.tasks[1].priority == 5)
        #expect(state.tasks[2].priority == 1) // id 3 moved to end

        // Test with invalid index (should return unchanged state)
        let unchangedState = sortedReducer.reduce(
            oldState: state,
            with: .updateTask(10, .increasePriority)
        )
        #expect(unchangedState == state)
    }

    @Test
    func comparableOffset() {
        // Test that array is sorted and positions are injected after updates
        struct Player: Hashable {
            var id: Int
            var name: String
            var score: Int
            var rank: Int = 0
        }

        struct LeaderboardState: Hashable {
            var players: [Player]
        }

        enum PlayerAction: Actionable {
            case addPoints(Int)
            case subtractPoints(Int)
        }

        enum LeaderboardAction: Actionable {
            case updatePlayer(Int, PlayerAction)

            static let prism = Prism<Self, (Int, PlayerAction)>(
                embed: { .updatePlayer($0, $1) },
                extract: { action in
                    if case let .updatePlayer(index, playerAction) = action {
                        return (index, playerAction)
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
                case let .subtractPoints(points):
                    state.score -= points
                }
                return state
            }
        }

        // Sort by score descending and inject rank (1-indexed)
        let leaderboardReducer = PlayerReducer().comparableOffset(
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
            players: [
                Player(id: 1, name: "Alice", score: 100),
                Player(id: 2, name: "Bob", score: 200),
                Player(id: 3, name: "Charlie", score: 150)
            ]
        )

        // Give Alice 150 points (100 -> 250), making her rank 1
        state = leaderboardReducer.reduce(
            oldState: state,
            with: .updatePlayer(0, .addPoints(150))
        )

        // Verify sorted order and ranks: Alice (250, rank 1), Bob (200, rank 2), Charlie (150, rank 3)
        #expect(state.players[0].name == "Alice")
        #expect(state.players[0].score == 250)
        #expect(state.players[0].rank == 1)

        #expect(state.players[1].name == "Bob")
        #expect(state.players[1].score == 200)
        #expect(state.players[1].rank == 2)

        #expect(state.players[2].name == "Charlie")
        #expect(state.players[2].score == 150)
        #expect(state.players[2].rank == 3)

        // Subtract 100 points from Bob (200 -> 100), moving him to rank 3
        state = leaderboardReducer.reduce(
            oldState: state,
            with: .updatePlayer(1, .subtractPoints(100))
        )

        // Verify new ranks: Alice (250, rank 1), Charlie (150, rank 2), Bob (100, rank 3)
        #expect(state.players[0].name == "Alice")
        #expect(state.players[0].rank == 1)

        #expect(state.players[1].name == "Charlie")
        #expect(state.players[1].rank == 2)

        #expect(state.players[2].name == "Bob")
        #expect(state.players[2].rank == 3)

        // Give Charlie 200 points (150 -> 350), making him rank 1
        state = leaderboardReducer.reduce(
            oldState: state,
            with: .updatePlayer(1, .addPoints(200))
        )

        // Verify new ranks: Charlie (350, rank 1), Alice (250, rank 2), Bob (100, rank 3)
        #expect(state.players[0].name == "Charlie")
        #expect(state.players[0].score == 350)
        #expect(state.players[0].rank == 1)

        #expect(state.players[1].name == "Alice")
        #expect(state.players[1].score == 250)
        #expect(state.players[1].rank == 2)

        #expect(state.players[2].name == "Bob")
        #expect(state.players[2].score == 100)
        #expect(state.players[2].rank == 3)

        // Test with invalid index (should return unchanged state)
        let unchangedState = leaderboardReducer.reduce(
            oldState: state,
            with: .updatePlayer(10, .addPoints(50))
        )
        #expect(unchangedState == state)
    }
}
