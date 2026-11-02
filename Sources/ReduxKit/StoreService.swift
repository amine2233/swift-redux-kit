/// A long-lived source of actions fed by something outside the store.
///
/// Where a ``Middleware`` reacts to an action and optionally answers with one more action,
/// a ``StoreService`` runs in the opposite direction: it observes an external source
/// (location updates, network reachability, a database, a socket, notifications) and emits an
/// action every time that source changes.
///
/// A service is started by awaiting `run(_:)` on a store, typically from the root view's `task`
/// modifier. Cancelling that task tears every service down.
///
/// ```swift
/// struct ReachabilityService: StoreService {
///     let monitor: NWPathMonitor
///
///     func actions() -> AsyncStream<AppAction> {
///         AsyncStream { continuation in
///             monitor.pathUpdateHandler = { path in
///                 continuation.yield(.reachabilityChanged(path.status == .satisfied))
///             }
///             continuation.onTermination = { _ in monitor.cancel() }
///             monitor.start(queue: .global())
///         }
///     }
/// }
/// ```
public protocol StoreService<Action>: Sendable {
    /// The action type this service emits.
    associatedtype Action: Sendable & Actionable

    /// The stream of actions produced by the observed source.
    ///
    /// Finish the stream when the source is exhausted; a service that never finishes keeps
    /// running until the task awaiting it is cancelled.
    ///
    /// - Returns: A stream of actions to feed into the store.
    func actions() -> AsyncStream<Action>
}

/// A ``StoreService`` built from a closure, for sources that already expose an `AsyncStream`.
///
/// ```swift
/// ClosureService { database.changes.map(AppAction.databaseChanged) }
/// ```
public struct ClosureService<Action: Sendable & Actionable>: StoreService {
    private let stream: @Sendable () -> AsyncStream<Action>

    /// Creates a service from a closure producing the action stream.
    ///
    /// - Parameter stream: A closure called once per run, returning the stream of actions.
    public init(_ stream: @Sendable @escaping () -> AsyncStream<Action>) {
        self.stream = stream
    }

    /// The stream of actions produced by the closure.
    ///
    /// - Returns: A stream of actions to feed into the store.
    public func actions() -> AsyncStream<Action> {
        stream()
    }
}

/// Runs every service concurrently, forwarding the actions they emit to `send`.
///
/// Returns once every service has finished its stream. Cancelling the calling task tears all of
/// them down. Shared by ``Store/run()`` and the `Storeable` convenience overloads.
///
/// - Parameters:
///   - services: The services to run concurrently.
///   - send: The closure fed with every emitted action.
package func runServices<Action: Sendable & Actionable>(
    _ services: [any StoreService<Action>],
    send: @Sendable @escaping (Action) async -> Void
) async {
    await withTaskGroup(of: Void.self) { group in
        for service in services {
            group.addTask {
                for await action in service.actions() {
                    await send(action)
                }
            }
        }
    }
}
