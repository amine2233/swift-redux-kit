import ReduxKit

extension Storeable where Self: Sendable {
    /// Runs the given services, forwarding every action they emit into the store.
    ///
    /// Use this overload for services that are not known when the store is built; services known up
    /// front are better declared with the store's `services:` parameter and started with `run()`.
    ///
    /// The call returns once every service has finished its stream. Cancelling the task that awaits
    /// this method tears all of them down, so the call site is whatever owns the store's lifetime —
    /// commonly a `task` modifier, but any `async` context works:
    ///
    /// ```swift
    /// Content()
    ///     .task { await store.run([LocationService(), ReachabilityService()]) }
    /// ```
    ///
    /// - Parameter services: The services to run concurrently.
    public func run(_ services: [any StoreService<Action>]) async {
        await runServices(services) { action in
            await send(action)
        }
    }

    /// Runs the given services, forwarding every action they emit into the store.
    ///
    /// - Parameter services: The services to run concurrently.
    public func run(_ services: any StoreService<Action>...) async {
        await run(services)
    }
}
