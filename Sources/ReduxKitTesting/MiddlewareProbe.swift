import ReduxKit
import Testing

/// A harness for testing a `Middleware` in isolation: assert which action (if any) it emits for a given
/// state and input action.
///
/// The probe is created against a fixed state. Each assertion runs the middleware's `process` for an
/// input action and checks the emitted action. Calls chain.
///
/// ```swift
/// await TestMiddleware().probe(state: State())
///     .expect(on: .sideEffect, emits: .increment)
///     .expectNoAction(on: .increment)
/// ```
public struct MiddlewareProbe<M: Middleware> {
    private let middleware: M

    /// The state the middleware is processed against.
    public let state: M.State

    init(middleware: M, state: M.State) {
        self.middleware = middleware
        self.state = state
    }

    /// Asserts that processing `action` emits `expected` (use `nil` to assert no action is emitted).
    /// - Parameters:
    ///   - action: The input action to process.
    ///   - expected: The action you expect the middleware to emit, or `nil` for none.
    ///   - sourceLocation: The source location of the call, for failure attribution.
    /// - Returns: The probe, for chaining.
    @discardableResult
    public func expect(
        on action: M.Action,
        emits expected: M.Action?,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async -> Self {
        let emitted = await middleware.process(state: state, with: action)
        if emitted != expected {
            Issue.record(
                """
                Middleware emission mismatch for "\(action)":
                  expected: \(describe(expected))
                  actual:   \(describe(emitted))
                """,
                sourceLocation: sourceLocation
            )
        }
        return self
    }

    /// Asserts that processing `action` emits no follow-up action.
    /// - Parameters:
    ///   - action: The input action to process.
    ///   - sourceLocation: The source location of the call, for failure attribution.
    /// - Returns: The probe, for chaining.
    @discardableResult
    public func expectNoAction(
        on action: M.Action,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async -> Self {
        await expect(on: action, emits: nil, sourceLocation: sourceLocation)
    }

    private func describe(_ action: M.Action?) -> String {
        action.map { "\($0)" } ?? "nil"
    }
}

extension Middleware {
    /// Creates a ``MiddlewareProbe`` for testing this middleware against `state`.
    /// - Parameter state: The state to process actions against.
    /// - Returns: A probe over this middleware.
    public func probe(state: State) -> MiddlewareProbe<Self> {
        MiddlewareProbe(middleware: self, state: state)
    }
}
