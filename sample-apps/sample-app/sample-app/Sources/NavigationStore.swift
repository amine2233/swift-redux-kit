import Foundation
import ReduxKit

/// Singleton navigation store following ReduxKit best practices
@MainActor
final class NavigationStore {
    /// Shared singleton instance
    static let shared = Store(
        initialState: State(),
        reducer: NavigationReducer(),
        middlewares: []
    )
}

// MARK: - State

extension NavigationStore {
    struct State: Sendable, Hashable {
        var path: [Destination] = []
    }

    enum Destination: Hashable, Sendable {
        case main
        case prismExample
        case keyedExample
        case offsetExample
        case filterOffsetExample
        case filteredKeyedExample
        case sortedOffsetExample
        case optionalExample
        case undoableExample
        case descriptiveUndoableExample
        case actionableUndoableExample
        case serviceExample
        // Add more destinations here as needed
    }
}

// MARK: - Action

extension NavigationStore {
    enum Action: Actionable {
        case push(Destination)
        case pop
        case popToRoot
        case setPath([Destination])
    }
}

// MARK: - Reducer

struct NavigationReducer: Reducer {
    func reduce(oldState: NavigationStore.State, with action: NavigationStore.Action) -> NavigationStore
        .State {
        var state = oldState

        switch action {
        case let .push(destination):
            state.path.append(destination)

        case .pop:
            guard !state.path.isEmpty else { return state }

            state.path.removeLast()

        case .popToRoot:
            state.path.removeAll()

        case let .setPath(path):
            state.path = path
        }

        return state
    }
}
