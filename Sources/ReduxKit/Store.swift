import Observation

/// Type that stores the state of the feature or module allowing feeding actions.
///
/// The ``Store`` type serves as the single source of truth for your state and handles state mutations through
/// actions.
/// It coordinates between the state, reducer, and middlewares to maintain a predictable state container.
@Observable @dynamicMemberLookup @MainActor
public final class Store<State: Sendable & Hashable, Action: Sendable & Actionable> {
    private var state: State
    private let reducer: any Reducer<State, Action>
    private let middlewares: any Collection<any Middleware<State, Action>>
    /// The services registered at initialisation.
    ///
    /// Exposed at package level so wrapping stores can run them through their own ``send(_:)``.
    package let services: [any StoreService<Action>]

    /// Creates an instance of `Store` with the folowing parameters.
    /// - Parameters:
    ///   - state: The initial state
    ///   - reducer: The reduce
    ///   - middlewares: The middlewares
    ///   - services: The services emitting actions from outside the store, started by ``run()``
    public init(
        initialState state: State,
        reducer: some Reducer<State, Action>,
        middlewares: some Collection<any Middleware<State, Action>>,
        services: [any StoreService<Action>] = []
    ) {
        self.state = state
        self.reducer = reducer
        self.middlewares = middlewares
        self.services = services
    }

    /// A subscript providing access to the state of the store.
    public subscript<T>(dynamicMember keyPath: KeyPath<State, T> & Sendable) -> T {
        state[keyPath: keyPath]
    }

    /// Use this method to mutate the state of the store by feeding actions.
    ///
    /// The reducer handles the action synchronously and updates `state` before any middleware runs,
    /// so middleware observes the post-reduction state when it processes the action.
    /// - Parameter action: An action defined in the reducer.
    public func send(_ action: Action) async {
        let newState = reducer.reduce(oldState: state, with: action)
        if newState != state {
            self.state = newState
        }
        await intercept(action)
    }

    /// Runs every service registered at initialisation, feeding their actions into the store.
    ///
    /// The call returns once every service has finished its stream. Cancelling the task that awaits
    /// this method tears all of them down, so the call site is whatever owns the store's lifetime — a
    /// view via the `task` modifier:
    ///
    /// ```swift
    /// Content()
    ///     .task { await store.run() }
    /// ```
    ///
    /// an app-lifetime store started once and never cancelled:
    ///
    /// ```swift
    /// init() {
    ///     Task { await AppStore.shared.run() }
    /// }
    /// ```
    ///
    /// or any `async` entry point, where it doubles as the main loop:
    ///
    /// ```swift
    /// static func main() async {
    ///     await store.run()
    /// }
    /// ```
    public func run() async {
        await runServices(services) { [self] action in
            await send(action)
        }
    }

    private func intercept(_ action: Action) async {
        for middleware in middlewares {
            if let nextAction = await middleware.process(state: state, with: action) {
                await self.send(nextAction)
            }
        }
    }

    /// Sets the state directly without going through the reducer.
    /// This method is package-internal and intended for use by UndoableStore.
    /// - Parameter newState: The state to set
    package func setState(_ newState: State) {
        if newState != state {
            self.state = newState
        }
    }
}

extension Store {
    /// Use this method to create another ``Store`` deriving from the current one.
    @available(*, deprecated, message: "Use multiple stores instead of derived store")
    public func derived<DerivedState: Hashable, DerivedAction: Hashable>(
        deriveState: @Sendable @escaping (State) -> DerivedState,
        deriveAction: @Sendable @escaping (DerivedAction) -> Action
    ) -> Store<DerivedState, DerivedAction> {
        let store = Store<DerivedState, DerivedAction>(
            initialState: deriveState(state),
            reducer: IdentityReducer(),
            middlewares: [
                ClosureMiddleware { [weak self] _, action in
                    guard let self else { return nil }

                    await self.send(deriveAction(action))
                    return nil
                }
            ]
        )

        enableStateObservation(for: store, deriveState: deriveState)

        return store
    }

    private func enableStateObservation<DerivedState: Hashable, DerivedAction: Hashable>(
        for store: Store<DerivedState, DerivedAction>,
        deriveState: @Sendable @escaping (State) -> DerivedState
    ) {
        withObservationTracking {
            let newState = deriveState(state)
            if store.state != newState {
                store.state = newState
            }
        } onChange: {
            Task {
                await self.enableStateObservation(for: store, deriveState: deriveState)
            }
        }
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension Store {
    /// Use this method to create a `SwiftUI.Binding` from any instance of `Store`.
    /// - Parameters:
    ///   - extract: The state extraction
    ///   - embed: The embed action
    ///
    /// - Returns: A `Binding` object that allows reading from the state using the extract and
    ///   embeding an action when the value is changed.
    public func binding<Value: Equatable>(
        extract: @escaping (State) -> Value,
        embed: @escaping (Value) -> Action
    ) -> Binding<Value> {
        .init(
            get: { extract(self.state) },
            set: { newValue, transaction in
                let action = embed(newValue)

                let oldValue = extract(self.state)
                guard newValue != oldValue else { return }

                withTransaction(transaction) {
                    self.state = self.reducer.reduce(
                        oldState: self.state, with: action
                    )
                }

                Task {
                    await self.intercept(action)
                }
            }
        )
    }
}
#endif

#if canImport(SwiftUI)
import SwiftUI

extension Store {
    /// Creates a `Binding` that allows two-way data binding between a state value and an action.
    ///
    /// - Parameters:
    ///   - keyPath: A key path to access a specific value from the current state.
    ///   - send: A closure that takes the updated value and returns an `Action` to be sent.
    ///
    /// - Returns: A `Binding` object that allows reading from the state using the key path and
    ///   sending an action when the value is changed.
    public func binding<Value: Equatable>(
        _ keyPath: KeyPath<State, Value>,
        send: @escaping (Value) -> Action
    ) -> Binding<Value> {
        .init(
            get: { self.state[keyPath: keyPath] },
            set: { newValue, transaction in
                let action = send(newValue)

                let oldValue = self.state[keyPath: keyPath]
                guard newValue != oldValue else { return }

                withTransaction(transaction) {
                    self.state = self.reducer.reduce(
                        oldState: self.state, with: action
                    )
                }

                Task {
                    await self.intercept(action)
                }
            }
        )
    }
}
#endif
