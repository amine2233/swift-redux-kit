import ReduxKit
import ReduxKitTesting
import Testing
@testable import sample_app

// Tests for the app's root feature (`AppStore.State` / `AppStore.Action` / `AppReducer` /
// `AppMiddleware`) using the `ReduxKitTesting` package.

@MainActor
struct AppStoreTests {
    // MARK: - Reducer (synchronous, isolated)

    @Test
    func finishLoadingClearsLoading() {
        AppReducer().probe(AppStore.State(isLoading: true, isAuthenticated: false))
            .send(.finishLoading)
            .expect { #expect($0.isLoading == false) }
    }

    @Test
    func authenticateSetsAuthenticatedAndStopsLoading() {
        AppReducer().probe(AppStore.State(isLoading: true, isAuthenticated: false))
            .send(.authenticate)
            .expect {
                #expect($0.isAuthenticated == true)
                #expect($0.isLoading == false)
            }
    }

    @Test
    func logoutClearsAuthentication() {
        expectReduce(
            AppReducer(),
            from: AppStore.State(isLoading: false, isAuthenticated: true),
            action: .logout,
            to: AppStore.State(isLoading: false, isAuthenticated: false)
        )
    }

    // MARK: - Middleware (async, isolated)

    @Test
    func middlewareIgnoresNonLaunchActions() async {
        // These actions are not intercepted, so the middleware emits nothing (fast — no sleep).
        await AppMiddleware().probe(state: AppStore.State())
            .expectNoAction(on: .finishLoading)
            .expectNoAction(on: .authenticate)
            .expectNoAction(on: .logout)
    }

    // MARK: - Store (full integration)

    @Test
    func launchFinishesLoadingViaMiddleware() async {
        let store = TestStore(
            initialState: AppStore.State(isLoading: false, isAuthenticated: false),
            reducer: AppReducer(),
            middlewares: [AppMiddleware()]
        )

        // `.appLaunched` flips `isLoading` on synchronously...
        await store.send(.appLaunched) { $0.isLoading = true }
        // ...then the middleware (simulated splash delay) dispatches `.finishLoading`.
        await store.receive(.finishLoading) { $0.isLoading = false }

        store.finish()
    }
}
