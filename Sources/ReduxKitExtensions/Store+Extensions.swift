import ReduxKit

extension Storeable {
    /// Dispatch a new action without blocking.
    ///
    /// This is a convenience method that wraps ``send(_:)`` in a Task, allowing
    /// synchronous code to dispatch actions without awaiting their completion.
    ///
    /// - Parameter action: An action to dispatch
    public func dispatch(_ action: Action) {
        Task { @MainActor in
            await send(action)
        }
    }

    /// Use this method to send a thunk resulting an action to mutate the store
    /// - Parameter thunk: The thunk function send
    public func send(thunk: @Sendable @escaping () async -> Action) async {
        let action = await thunk()
        await send(action)
    }

    /// Dispatch a new action using a thunk without blocking
    ///
    /// - Parameter thunk: A thunk function that produces an action
    public func dispatch(thunk: @Sendable @escaping () async -> Action) {
        Task { @MainActor in
            await send(thunk: thunk)
        }
    }
}
