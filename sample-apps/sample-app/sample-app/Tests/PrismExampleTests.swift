import ReduxKit
import ReduxKitTesting
import Testing
@testable import sample_app

// Tests for the Prism composition example (`ExampleAppState` / `ExampleAppAction` /
// `ExampleAppReducer`) — a parent reducer that delegates to a `.lifted()` child reducer.
// This shows `ReduxKitTesting` works through prism-composed reducers, including nested state.

@MainActor
struct PrismExampleTests {
    /// Parent-level actions handled directly by the parent reducer. No middleware → no `receive`.
    @Test
    func parentActionsToggleLogin() async {
        let store = TestStore(initialState: ExampleAppState(), reducer: ExampleAppReducer())

        await store.send(.login) { $0.isLoggedIn = true }
        await store.send(.logout) { $0.isLoggedIn = false }

        store.finish()
    }

    /// Child actions wrapped in `.userProfile(...)` flow through the lifted reducer and mutate the
    /// nested `userProfile` state.
    @Test
    func childActionsUpdateNestedState() async {
        let store = TestStore(initialState: ExampleAppState(), reducer: ExampleAppReducer())

        await store.send(.userProfile(.startEditing)) { $0.userProfile.isEditing = true }
        await store.send(.userProfile(.updateName("Ada"))) { $0.userProfile.name = "Ada" }
        await store
            .send(.userProfile(.updateEmail("ada@example.com"))) { $0.userProfile.email = "ada@example.com" }
        await store.send(.userProfile(.stopEditing)) { $0.userProfile.isEditing = false }

        store.finish()
    }

    /// The same composition tested synchronously with a `ReducerProbe`.
    @Test
    func reducerProbeMixesParentAndChild() {
        ExampleAppReducer().probe(ExampleAppState())
            .send(.userProfile(.updateName("Grace")))
            .expect { #expect($0.userProfile.name == "Grace") }
            .send(.login)
            .expect {
                #expect($0.isLoggedIn == true)
                #expect($0.userProfile.name == "Grace") // unchanged by the parent action
            }
    }
}
