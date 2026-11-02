import Foundation
import ReduxKit

/// Protocol defining the core interface for store types that can handle actions.
///
/// Types conforming to ``Storeable`` provide a standardized interface for sending actions
/// to mutate state. This allows different store implementations (like ``Store``, ``UndoableStore``,
/// and ``ActionableUndoableStore``) to share common functionality through protocol extensions.
@MainActor
public protocol Storeable<State, Action> {
    /// The state type managed by the store.
    associatedtype State: Sendable & Hashable
    /// The action type that the store can process.
    associatedtype Action: Sendable & Actionable

    /// Use this method to mutate the state by feeding actions.
    ///
    /// This is the core method that all store implementations must provide.
    /// The exact behavior may vary by implementation (e.g., stores with undo/redo
    /// may record history).
    ///
    /// - Parameter action: An action to process
    func send(_ action: Action) async
}

extension Store: Storeable {}
