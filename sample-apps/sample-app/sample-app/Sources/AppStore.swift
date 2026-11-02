import Foundation
import ReduxKit

/// Main application store following ReduxKit best practices
@MainActor
final class AppStore {
    /// Shared singleton instance
    static let shared = Store(
        initialState: State(),
        reducer: AppReducer(),
        middlewares: [AppMiddleware()]
    )
}

// MARK: - State

extension AppStore {
    struct State: Sendable, Hashable {
        var isLoading: Bool = true
        var isAuthenticated: Bool = false

        // Add feature-specific states here
    }
}

// MARK: - Action

extension AppStore {
    enum Action: Actionable {
        case appLaunched
        case finishLoading
        case authenticate
        case logout

        // Add feature-specific actions here
    }
}

// MARK: - Reducer

struct AppReducer: Reducer {
    func reduce(oldState: AppStore.State, with action: AppStore.Action) -> AppStore.State {
        var state = oldState

        switch action {
        case .appLaunched:
            state.isLoading = true

        case .finishLoading:
            state.isLoading = false

        case .authenticate:
            state.isAuthenticated = true
            state.isLoading = false

        case .logout:
            state.isAuthenticated = false
        }

        return state
    }
}

// MARK: - Middleware

struct AppMiddleware: Middleware {
    func process(state: AppStore.State, with action: AppStore.Action) async -> AppStore.Action? {
        switch action {
        case .appLaunched:
            // Simulate splash screen loading
            try? await Task.sleep(for: .seconds(2))
            return .finishLoading

        default:
            return nil
        }
    }
}
