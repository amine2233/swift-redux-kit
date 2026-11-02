import ReduxKit
import Testing

/// A fluent harness for testing a `Reducer` in isolation, without a store or middleware.
///
/// A probe holds a running state. `send(_:)` reduces an action and advances the state; `expect(_:)`
/// asserts the current state. Calls chain, so a single expression reads as a sequence of given/when/then
/// steps.
///
/// ```swift
/// CounterReducer().probe(State(counter: 0))
///     .send(.increment)
///     .expect(State(counter: 1))
///     .send(.increment)
///     .expect { #expect($0.counter == 2) }
/// ```
public struct ReducerProbe<R: Reducer> {
    private let reducer: R

    /// The current state after the actions sent so far.
    public private(set) var state: R.State

    init(reducer: R, state: R.State) {
        self.reducer = reducer
        self.state = state
    }

    /// Reduces `action` against the current state and advances the probe to the produced state.
    /// - Parameter action: The action to reduce.
    /// - Returns: The advanced probe, for chaining.
    @discardableResult
    public func send(_ action: R.Action) -> Self {
        var copy = self
        copy.state = reducer.reduce(oldState: state, with: action)
        return copy
    }

    /// Asserts the current state equals `expected`.
    /// - Parameters:
    ///   - expected: The state you expect.
    ///   - sourceLocation: The source location of the call, for failure attribution.
    /// - Returns: The probe, unchanged, for chaining.
    @discardableResult
    public func expect(
        _ expected: R.State,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> Self where R.State: Equatable {
        if state != expected {
            Issue.record(
                """
                State mismatch:
                  expected: \(expected)
                  actual:   \(state)
                """,
                sourceLocation: sourceLocation
            )
        }
        return self
    }

    /// Runs a custom assertion against the current state, for example with `#expect`.
    /// - Parameter assert: A closure that inspects the current state.
    /// - Returns: The probe, unchanged, for chaining.
    @discardableResult
    public func expect(_ assert: (R.State) -> Void) -> Self {
        assert(state)
        return self
    }
}

extension Reducer {
    /// Creates a ``ReducerProbe`` for testing this reducer starting from `initialState`.
    /// - Parameter initialState: The state the probe starts from.
    /// - Returns: A fluent probe over this reducer.
    public func probe(_ initialState: State) -> ReducerProbe<Self> {
        ReducerProbe(reducer: self, state: initialState)
    }
}

/// Asserts that reducing `action` from `state` produces `expected`, in a single call.
/// - Parameters:
///   - reducer: The reducer under test.
///   - state: The state to reduce from.
///   - action: The action to reduce.
///   - expected: The state you expect the reducer to produce.
///   - sourceLocation: The source location of the call, for failure attribution.
public func expectReduce<R: Reducer>(
    _ reducer: R,
    from state: R.State,
    action: R.Action,
    to expected: R.State,
    sourceLocation: SourceLocation = #_sourceLocation
) where R.State: Equatable {
    let actual = reducer.reduce(oldState: state, with: action)
    if actual != expected {
        Issue.record(
            """
            State mismatch after "\(action)":
              expected: \(expected)
              actual:   \(actual)
            """,
            sourceLocation: sourceLocation
        )
    }
}
