import ReduxKit
import Testing

/// A test harness that drives a `Store` and lets you assert, with sugar syntax, the state produced by
/// each action *and* the follow-up actions emitted by middleware.
///
/// `TestStore` wraps the reducer you give it so it can record every transition the store produces.
/// Sending an action runs the reducer synchronously and then the full middleware cascade (each
/// middleware follow-up is awaited to completion), so by the time `send(_:)` returns every action has
/// already been reduced. You assert the immediate transition with `send(_:_:)` and each subsequent
/// middleware-emitted action with `receive(_:_:)`.
///
/// ```swift
/// @MainActor func testCounter() async {
///     let store = TestStore(
///         initialState: State(),
///         reducer: TestReducer(),
///         middlewares: [TestMiddleware()]
///     )
///
///     await store.send(.increment) { $0.counter = 1 }    // assert state after the sent action
///     await store.send(.sideEffect)                       // no direct state change
///     await store.receive(.increment) { $0.counter = 2 }  // middleware-emitted follow-up + state
///     store.finish()                                      // fail if any emitted action was unasserted
/// }
/// ```
///
/// ### Exhaustivity
///
/// By default the store is *exhaustive*: every action the cascade reduces must be accounted for with a
/// matching `receive(_:_:)`, otherwise `finish()` records a test failure. Exhaustivity is keyed on
/// reducer invocations, not on state changes — a follow-up action whose reducer leaves the state
/// unchanged still records a transition and must be received. Set ``exhaustivity`` to
/// ``Exhaustivity/disabled``
/// to assert only the immediate transition of each `send` and silently drain the rest of the cascade.
///
/// - Note: `receive(_:_:)` never waits or times out — the cascade has already completed inside
///   `send(_:_:)`. Middleware that performs real delays (for example `Task.sleep`) blocks `send` for
///   that wall-clock time; inject a clock if your tests need to stay fast.
@MainActor
public final class TestStore<State: Sendable & Hashable, Action: Sendable & Actionable> {
    /// Controls whether every emitted action must be asserted.
    public enum Exhaustivity: Sendable {
        /// `finish()` fails if any reduced action was not consumed by a `receive(_:_:)`.
        case enabled
        /// Follow-up actions are drained silently; only the immediate transition of each `send` is asserted.
        case disabled
    }

    /// Whether the store enforces that every emitted action is received. Defaults to
    /// ``Exhaustivity/enabled``.
    public var exhaustivity: Exhaustivity = .enabled

    /// The state at the current assertion cursor (the most recently asserted transition).
    public private(set) var state: State

    private let store: Store<State, Action>
    private let log: TransitionLog<Action, State>
    private var cursor = 0

    /// Creates a test store wrapping the given reducer and middlewares.
    /// - Parameters:
    ///   - initialState: The initial state.
    ///   - reducer: The reducer under test.
    ///   - middlewares: The middlewares under test.
    ///   - services: The services under test, started by ``run()``.
    public init(
        initialState: State,
        reducer: some Reducer<State, Action>,
        middlewares: some Collection<any Middleware<State, Action>>,
        services: [any StoreService<Action>] = []
    ) {
        let log = TransitionLog<Action, State>()
        self.log = log
        self.state = initialState
        self.store = Store(
            initialState: initialState,
            reducer: RecordingReducer(base: reducer, log: log),
            middlewares: middlewares,
            services: services
        )
    }

    /// Creates a test store wrapping the given reducer, with no middlewares.
    /// - Parameters:
    ///   - initialState: The initial state.
    ///   - reducer: The reducer under test.
    public convenience init(
        initialState: State,
        reducer: some Reducer<State, Action>
    ) {
        self.init(
            initialState: initialState,
            reducer: reducer,
            middlewares: [any Middleware<State, Action>]()
        )
    }

    /// Runs every registered service, feeding the actions they emit into the store under test.
    ///
    /// Emitted actions land in the transition log like any middleware follow-up, so they are asserted
    /// with `receive(_:_:)`. Drive the services from the test, then await the run before asserting:
    ///
    /// ```swift
    /// let task = Task { await store.run() }
    /// continuation.yield(.tick)
    /// continuation.finish()
    /// await task.value
    /// await store.receive(.tick) { $0.ticks = 1 }
    /// ```
    public func run() async {
        await store.run()
    }

    /// Sends an action and asserts the state produced by reducing *only* that action.
    ///
    /// The trailing closure receives a mutable copy of the current asserted state; mutate it to describe
    /// the state you expect after this action. Any difference from the actual state is reported as a test
    /// failure. After the assertion, follow-up actions emitted by middleware remain pending and must be
    /// consumed with `receive(_:_:)` (when exhaustive).
    /// - Parameters:
    ///   - action: The action to send.
    ///   - sourceLocation: The source location of the call, for failure attribution.
    ///   - update: A closure that mutates the expected state in place.
    public func send(
        _ action: Action,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ update: (inout State) -> Void = { _ in }
    ) async {
        if cursor < log.entries.count {
            Issue.record(
                """
                Cannot send "\(action)" while \(log.entries.count - cursor) received action(s) are pending. \
                Assert them with receive(_:) first: \(pendingActions()).
                """,
                sourceLocation: sourceLocation
            )
        }

        let start = log.entries.count
        await store.send(action)

        guard start < log.entries.count else {
            Issue.record(
                #"Sending "\#(action)" produced no transition; the reducer was never invoked."#,
                sourceLocation: sourceLocation
            )
            return
        }

        assertTransition(at: start, expectedAction: action, update: update, sourceLocation: sourceLocation)
        cursor = start + 1

        if exhaustivity == .disabled {
            drainPending()
        }
    }

    /// Asserts that the next action emitted by middleware matches `action`, and that it produced the
    /// expected state.
    ///
    /// Follow-up actions are reported in depth-first dispatch order. The trailing closure mutates a copy
    /// of the current asserted state to describe what you expect after this action.
    /// - Parameters:
    ///   - action: The follow-up action you expect middleware to have emitted.
    ///   - sourceLocation: The source location of the call, for failure attribution.
    ///   - update: A closure that mutates the expected state in place.
    public func receive(
        _ action: Action,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ update: (inout State) -> Void = { _ in }
    ) async {
        guard cursor < log.entries.count else {
            Issue.record(
                #"Expected to receive "\#(action)" but no action was emitted."#,
                sourceLocation: sourceLocation
            )
            return
        }

        assertTransition(at: cursor, expectedAction: action, update: update, sourceLocation: sourceLocation)
        cursor += 1
    }

    /// Verifies that no emitted actions were left unasserted.
    ///
    /// In ``Exhaustivity/enabled`` mode this records a test failure if any reduced action was not consumed
    /// by a `receive(_:_:)`. In ``Exhaustivity/disabled`` mode it does nothing. Call it at the end of a test.
    /// - Parameter sourceLocation: The source location of the call, for failure attribution.
    public func finish(sourceLocation: SourceLocation = #_sourceLocation) {
        guard exhaustivity == .enabled, cursor < log.entries.count else { return }

        Issue.record(
            """
            \(log.entries.count - cursor) action(s) were emitted but never received: \(pendingActions()). \
            Assert them with receive(_:) or set exhaustivity to .disabled.
            """,
            sourceLocation: sourceLocation
        )
    }

    // MARK: - Private

    private func assertTransition(
        at index: Int,
        expectedAction: Action,
        update: (inout State) -> Void,
        sourceLocation: SourceLocation
    ) {
        let entry = log.entries[index]

        if entry.action != expectedAction {
            Issue.record(
                #"Expected action "\#(expectedAction)" but received "\#(entry.action)"."#,
                sourceLocation: sourceLocation
            )
        }

        var expected = state
        update(&expected)

        if entry.state != expected {
            Issue.record(
                """
                State mismatch after "\(entry.action)":
                  expected: \(expected)
                  actual:   \(entry.state)
                """,
                sourceLocation: sourceLocation
            )
        }

        state = entry.state
    }

    private func drainPending() {
        if let last = log.entries.last {
            state = last.state
        }
        cursor = log.entries.count
    }

    private func pendingActions() -> String {
        log.entries[cursor...].map { "\($0.action)" }.joined(separator: ", ")
    }
}
