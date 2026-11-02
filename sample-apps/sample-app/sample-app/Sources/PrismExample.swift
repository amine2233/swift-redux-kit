import Foundation
import ReduxKit
import ReduxKitExtensions
import SwiftUI

// MARK: - Prism Example: Composing Feature Reducers

// This example demonstrates how to use Prism to compose feature reducers into a parent app reducer.
//
// The problem:
// - You have a parent AppState containing child feature states
// - Each feature has its own reducer that works on its local state
// - You need the parent reducer to delegate actions to child reducers
//
// The solution:
// - Use Prism to "lift" the child reducer to work on the parent state
// - Prism provides `embed` (Target -> Source) and `extract` (Source -> Target?)
// - The lifted reducer only runs when the action matches the prism

// MARK: - Child Feature: User Profile

/// Child feature state
struct UserProfileState: Sendable, Hashable {
    var name: String = ""
    var email: String = ""
    var isEditing: Bool = false
}

/// Child feature actions
enum UserProfileAction: Actionable {
    case updateName(String)
    case updateEmail(String)
    case startEditing
    case stopEditing
}

/// Child feature reducer - only knows about UserProfile domain
struct UserProfileReducer: Reducer {
    func reduce(oldState: UserProfileState, with action: UserProfileAction) -> UserProfileState {
        var state = oldState

        switch action {
        case let .updateName(name):
            state.name = name

        case let .updateEmail(email):
            state.email = email

        case .startEditing:
            state.isEditing = true

        case .stopEditing:
            state.isEditing = false
        }

        return state
    }
}

// MARK: - Parent App State & Actions

/// Parent app state containing the child feature
struct ExampleAppState: Sendable, Hashable {
    var userProfile: UserProfileState = .init()
    var isLoggedIn: Bool = false
}

/// Parent app actions - includes child actions as associated values
enum ExampleAppAction: Actionable {
    case login
    case logout
    case userProfile(UserProfileAction) // Child actions wrapped in parent action
}

// MARK: - Prism Definition

extension Prism where Source == ExampleAppAction, Target == UserProfileAction {
    /// Prism that lifts UserProfileAction into ExampleAppAction
    static var userProfile: Prism<ExampleAppAction, UserProfileAction> {
        Prism(
            // embed: Convert child action to parent action
            embed: { childAction in
                .userProfile(childAction)
            },
            // extract: Extract child action from parent action (returns nil if not matching)
            extract: { parentAction in
                guard case let .userProfile(childAction) = parentAction else {
                    return nil
                }

                return childAction
            }
        )
    }
}

// MARK: - Parent App Reducer with Lifted Child

struct ExampleAppReducer: Reducer {
    func reduce(oldState: ExampleAppState, with action: ExampleAppAction) -> ExampleAppState {
        var state = oldState

        // Handle parent-level actions
        switch action {
        case .login:
            state.isLoggedIn = true

        case .logout:
            state.isLoggedIn = false
            // Could reset user profile here if needed

        case .userProfile:
            // Don't handle here - let the lifted reducer handle it
            break
        }

        // Apply the lifted child reducer using Prism
        // It will only modify state if the action matches the prism
        let userProfileReducer = UserProfileReducer().lifted(
            keyPath: \ExampleAppState.userProfile, // Where the child state lives in parent
            prism: .userProfile // How to extract child actions from parent actions
        )
        state = userProfileReducer.reduce(oldState: state, with: action)

        return state
    }
}

// MARK: - SwiftUI Example View

struct PrismExampleView: View {
    @Environment(Store<ExampleAppState, ExampleAppAction>.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Login Status
                Text(store.isLoggedIn ? "Logged In ✓" : "Logged Out")
                    .font(.headline)
                    .foregroundStyle(store.isLoggedIn ? .green : .red)

                Divider()

                // User Profile Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("User Profile")
                        .font(.title2)
                        .bold()

                    // Name field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if store.userProfile.isEditing {
                            TextField("Enter name", text: Binding(
                                get: { store.userProfile.name },
                                set: { store.dispatch(.userProfile(.updateName($0))) }
                            ))
                            .textFieldStyle(.roundedBorder)
                        } else {
                            Text(store.userProfile.name.isEmpty ? "Not set" : store.userProfile.name)
                                .foregroundStyle(store.userProfile.name.isEmpty ? .secondary : .primary)
                        }
                    }

                    // Email field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if store.userProfile.isEditing {
                            TextField("Enter email", text: Binding(
                                get: { store.userProfile.email },
                                set: { store.dispatch(.userProfile(.updateEmail($0))) }
                            ))
                            .textFieldStyle(.roundedBorder)
                        } else {
                            Text(store.userProfile.email.isEmpty ? "Not set" : store.userProfile.email)
                                .foregroundStyle(store.userProfile.email.isEmpty ? .secondary : .primary)
                        }
                    }

                    // Edit toggle
                    Button {
                        if store.userProfile.isEditing {
                            store.dispatch(.userProfile(.stopEditing))
                        } else {
                            store.dispatch(.userProfile(.startEditing))
                        }
                    } label: {
                        Text(store.userProfile.isEditing ? "Stop Editing" : "Start Editing")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(store.userProfile.isEditing ? Color.red : Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Divider()

                // Login/Logout
                Button {
                    if store.isLoggedIn {
                        store.dispatch(.logout)
                    } else {
                        store.dispatch(.login)
                    }
                } label: {
                    Text(store.isLoggedIn ? "Logout" : "Login")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(store.isLoggedIn ? Color.red : Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Explanation
                VStack(alignment: .leading, spacing: 8) {
                    Text("How Prism Works:")
                        .font(.headline)

                    Group {
                        Text("• Parent actions (.login, .logout) handled by parent reducer")
                        Text("• Child actions wrapped: .userProfile(.updateName(...))")
                        Text("• Prism extracts child action and passes to child reducer")
                        Text("• Child reducer operates on userProfile keyPath")
                        Text("• Result: Clean separation of concerns!")
                    }
                    .font(.caption)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
        }
        .navigationTitle("Prism Example")
    }
}

// MARK: - Preview

#Preview {
    let store = Store(
        initialState: ExampleAppState(),
        reducer: ExampleAppReducer(),
        middlewares: []
    )

    return NavigationStack {
        PrismExampleView()
            .environment(store)
    }
}

// MARK: - Key Takeaways

// 1. PRISM PURPOSE:
//   - Allows child reducers to work on nested state within parent state
//   - Provides clean composition of feature modules
//
// 2. PRISM STRUCTURE:
//   - `embed`: Wraps child action in parent action (.userProfile(...))
//   - `extract`: Unwraps parent action to get child action (returns nil if not matching)
//
// 3. LIFTED REDUCER:
//   - `.lifted(keyPath:prism:)` creates a reducer that:
//     * Works on parent state
//     * Only runs when prism extracts a matching action
//     * Modifies the child state at keyPath
//
// 4. BENEFITS:
//   - Each feature has independent State/Action/Reducer
//   - Parent doesn't need to know child reducer logic
//   - Child reducer stays pure and testable
//   - Easy to add/remove features
//
// 5. COMMON PATTERN:
//   - Define child feature (State, Action, Reducer)
//   - Add child state to parent state as property
//   - Wrap child actions in parent action enum
//   - Create Prism extension for extraction
//   - Use .lifted() in parent reducer
//
// 6. EXAMPLE FLOW:
//   User clicks "Start Editing" button
//   → Dispatches: .userProfile(.startEditing)
//   → Parent reducer sees action
//   → Lifted reducer's prism extracts .startEditing
//   → UserProfileReducer sets isEditing = true
//   → State updates, UI re-renders
