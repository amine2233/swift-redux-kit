import ReduxKit

/// Protocol defining the interface for store types that support undo/redo operations.
///
/// Types conforming to ``UndoableStoreable`` extend the basic ``Storeable`` interface
/// with undo and redo capabilities. This allows different undoable store implementations
/// to share common functionality through protocol extensions.
@MainActor
public protocol UndoableStoreable<State, Action>: Storeable {
    /// Undoes the last action by restoring the previous state.
    ///
    /// The exact behavior depends on the implementation:
    /// - ``UndoableStore`` and ``DescriptiveUndoableStore`` restore previous state snapshots
    /// - ``ActionableUndoableStore`` dispatches inverse actions through middleware
    ///
    /// - Returns: `true` if undo was performed, `false` if nothing to undo
    @discardableResult
    func undo() async -> Bool

    /// Redoes the last undone action.
    ///
    /// The exact behavior depends on the implementation:
    /// - ``UndoableStore`` and ``DescriptiveUndoableStore`` restore future state snapshots
    /// - ``ActionableUndoableStore`` dispatches the original action through middleware
    ///
    /// - Returns: `true` if redo was performed, `false` if nothing to redo
    @discardableResult
    func redo() async -> Bool

    /// Whether undo is available.
    var canUndo: Bool { get }

    /// Whether redo is available.
    var canRedo: Bool { get }
}

extension UndoableStoreable {
    /// Dispatches an undo operation without blocking.
    ///
    /// This is a convenience method that wraps ``undo()`` in a Task, allowing
    /// synchronous code to trigger undo without awaiting its completion.
    public func undoDispatch() {
        Task { @MainActor in
            await undo()
        }
    }

    /// Dispatches a redo operation without blocking.
    ///
    /// This is a convenience method that wraps ``redo()`` in a Task, allowing
    /// synchronous code to trigger redo without awaiting its completion.
    public func redoDispatch() {
        Task { @MainActor in
            await redo()
        }
    }
}
