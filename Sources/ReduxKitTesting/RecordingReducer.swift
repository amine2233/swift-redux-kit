import ReduxKit

/// An ordered, mutable record of the state transitions produced while a ``TestStore`` drives a `Store`.
///
/// Each entry pairs the action that was reduced with the state the reducer produced for it. Because
/// `Store.send` calls the reducer exactly once per action — for the action you send and for every
/// follow-up action a middleware dispatches — the log captures the full ordered cascade of a single
/// `send`, which ``TestStore`` then walks with `send(_:)` and `receive(_:)`.
///
/// This is a reference type so the recording reducer and the test store share a single growing log.
/// All access happens on the main actor inside `Store.send` (which is `@MainActor`), so the mutation
/// is serialized in practice.
final class TransitionLog<Action: Actionable, State: Hashable> {
    /// The recorded transitions, in the order the reducer produced them.
    var entries: [(action: Action, state: State)] = []
}

/// A `Reducer` decorator that forwards to a base reducer and records every transition it produces.
///
/// ``TestStore`` plugs this into a real `Store` in place of the user's reducer so it can observe the
/// intermediate states of a middleware cascade without reaching into the store's private state.
struct RecordingReducer<Base: Reducer>: Reducer {
    let base: Base
    let log: TransitionLog<Base.Action, Base.State>

    func reduce(oldState: Base.State, with action: Base.Action) -> Base.State {
        let newState = base.reduce(oldState: oldState, with: action)
        log.entries.append((action, newState))
        return newState
    }
}
