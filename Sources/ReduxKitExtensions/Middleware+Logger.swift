import ReduxKit

/// A middleware that logs Redux actions and state changes to the console for debugging purposes.
///
/// `LoggerMiddleware` is a generic debugging tool that intercepts actions in a Redux flow
/// and prints detailed information about each action and the current state. This is particularly
/// useful during development to trace state changes and understand the flow of actions through
/// your application.
///
/// ## Usage
///
/// Add the logger middleware to your Redux store configuration:
///
/// ```swift
/// let store = Store(
///     initialState: AppState(),
///     reducer: appReducer,
///     middleware: [LoggerMiddleware<AppState, AppAction>()]
/// )
/// ```
///
/// ## Output Format
///
/// The middleware produces console output in the following format:
///
/// ```
/// ------ ACTION Start ------
/// Received [ActionName]
/// Current state:
/// [State description]
/// ------ ACTION End ------
/// ```
///
/// ## Generic Parameters
///
/// - `State`: The type of the application state. Must conform to `Sendable` for thread safety.
/// - `Action`: The type of actions processed by the store. Must conform to both `Sendable` and `Actionable`.
///
/// ## Thread Safety
///
/// This middleware is designed to work with Swift's concurrency model and requires both
/// `State` and `Action` types to be `Sendable`, ensuring safe usage across different
/// execution contexts.
///
/// ## Performance Considerations
///
/// Since this middleware logs every action and state, it should typically only be used
/// in debug builds to avoid performance overhead and excessive console output in production.
///
/// ```swift
/// #if DEBUG
/// let middleware: [any Middleware] = [LoggerMiddleware<AppState, AppAction>()]
/// #else
/// let middleware: [any Middleware] = []
/// #endif
/// ```
public struct LoggerMiddleware<State: Sendable & Hashable, Action: Sendable & Actionable>: Middleware {
    /// Creates a new logger middleware instance.
    ///
    /// The logger middleware requires no configuration and can be instantiated directly.
    public init() {}

    /// Processes an action by logging it along with the current state, then passes the action through
    /// unchanged.
    ///
    /// This method is called for every action that flows through the Redux store. It logs:
    /// - The action that was dispatched
    /// - The current state at the time of the action
    ///
    /// The action is always passed through unchanged, making this middleware purely observational.
    ///
    /// - Parameters:
    ///   - state: The current state of the application
    ///   - action: The action being processed
    /// - Returns: The same action that was passed in, allowing it to continue through the middleware chain
    public func process(state: State, with action: Action) async -> Action? {
        print("------ ACTION Start ------")
        print("Received [\(action)]")
        print("Current state:")
        print(state)
        print("------ ACTION End ------")
        return action
    }
}
