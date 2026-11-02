import Foundation
import ReduxKit
import ReduxKitExtensions
import SwiftUI

// MARK: - Optional Reducer Example: Managing Optional State

// This example demonstrates how to use .optional() to manage state that may or may not exist.
//
// The problem:
// - You have a child state that is optional (e.g., user session, active order, editing state)
// - The child state can be nil or present
// - You need to apply a child reducer only when the state exists
// - Parent needs to handle creation and removal of the optional state
//
// The solution:
// - Store child state as Optional<ChildState>
// - Use Prism to extract child actions from parent actions
// - Use .optional() to lift the child reducer to work on optional state
// - The optional reducer only runs if the state is not nil

// MARK: - Child Feature: User Session

/// User session state (only exists when logged in)
struct UserSessionState: Sendable, Hashable {
    var username: String
    var email: String
    var loginTime: Date
    var lastActivity: Date
    var preferences: Preferences

    struct Preferences: Sendable, Hashable {
        var notificationsEnabled: Bool = true
        var darkMode: Bool = false
        var autoSave: Bool = true
    }

    var sessionDuration: String {
        let interval = Date().timeIntervalSince(loginTime)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Actions for user session
enum UserSessionAction: Actionable {
    case updateUsername(String)
    case updateEmail(String)
    case updateLastActivity
    case toggleNotifications
    case toggleDarkMode
    case toggleAutoSave
}

/// Reducer for user session
struct UserSessionReducer: Reducer {
    func reduce(oldState: UserSessionState, with action: UserSessionAction) -> UserSessionState {
        var state = oldState

        switch action {
        case let .updateUsername(username):
            state.username = username

        case let .updateEmail(email):
            state.email = email

        case .updateLastActivity:
            state.lastActivity = Date()

        case .toggleNotifications:
            state.preferences.notificationsEnabled.toggle()

        case .toggleDarkMode:
            state.preferences.darkMode.toggle()

        case .toggleAutoSave:
            state.preferences.autoSave.toggle()
        }

        return state
    }
}

// MARK: - Parent: App State & Actions

/// Parent state containing optional user session
struct OptionalExampleAppState: Sendable, Hashable {
    var userSession: UserSessionState?
    var isLoading: Bool = false
    var loginAttempts: Int = 0

    var isLoggedIn: Bool {
        userSession != nil
    }
}

/// Parent actions - includes optional child actions
enum OptionalExampleAppAction: Actionable {
    case login(username: String, email: String)
    case logout
    case userSession(UserSessionAction) // Actions for when session exists
}

// MARK: - Prism for Optional Actions

extension Prism where Source == OptionalExampleAppAction, Target == UserSessionAction {
    /// Prism that extracts UserSessionAction from OptionalExampleAppAction
    static var userSession: Prism<OptionalExampleAppAction, UserSessionAction> {
        Prism(
            // embed: Wrap child action into parent action
            embed: { childAction in
                .userSession(childAction)
            },
            // extract: Extract child action from parent action
            extract: { parentAction in
                guard case let .userSession(action) = parentAction else {
                    return nil
                }

                return action
            }
        )
    }
}

// MARK: - Parent Reducer with Optional Child

struct OptionalExampleAppReducer: Reducer {
    func reduce(
        oldState: OptionalExampleAppState,
        with action: OptionalExampleAppAction
    ) -> OptionalExampleAppState {
        var state = oldState

        // Handle parent-level actions
        switch action {
        case let .login(username, email):
            // Create the session (make it non-nil)
            state.userSession = UserSessionState(
                username: username,
                email: email,
                loginTime: Date(),
                lastActivity: Date(),
                preferences: UserSessionState.Preferences()
            )
            state.loginAttempts += 1

        case .logout:
            // Remove the session (make it nil)
            state.userSession = nil

        case .userSession:
            // Don't handle here - let the optional reducer handle it
            break
        }

        // Apply the optional child reducer using Prism
        // It will only run if userSession is not nil
        let optionalReducer = UserSessionReducer().optional().lifted(
            keyPath: \OptionalExampleAppState.userSession,
            prism: .userSession
        )
        state = optionalReducer.reduce(oldState: state, with: action)

        return state
    }
}

// MARK: - SwiftUI Example View

struct OptionalExampleView: View {
    @Environment(Store<OptionalExampleAppState, OptionalExampleAppAction>.self) private var store
    @State private var showingLoginSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Login Status
                statusSection

                Divider()

                if store.isLoggedIn, let session = store.userSession {
                    // Session Details
                    sessionDetailsSection(session: session)

                    Divider()

                    // Preferences
                    preferencesSection(session: session)

                    Divider()

                    // Logout Button
                    logoutButton
                } else {
                    // Login Prompt
                    loginPromptSection
                }

                // Explanation
                explanationSection
            }
            .padding()
        }
        .navigationTitle("Optional Example")
        .sheet(isPresented: $showingLoginSheet) {
            LoginSheet()
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        VStack(spacing: 12) {
            Image(systemName: store.isLoggedIn ? "person.circle.fill" : "person.circle")
                .font(.system(size: 60))
                .foregroundStyle(store.isLoggedIn ? .green : .gray)

            Text(store.isLoggedIn ? "Logged In" : "Not Logged In")
                .font(.title2)
                .bold()

            if store.loginAttempts > 0 {
                Text("Total logins: \(store.loginAttempts)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sessionDetailsSection(session: UserSessionState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Details")
                .font(.headline)

            InfoCard(icon: "person.fill", label: "Username", value: session.username)
            InfoCard(icon: "envelope.fill", label: "Email", value: session.email)
            InfoCard(icon: "clock.fill", label: "Session Duration", value: session.sessionDuration)
            InfoCard(
                icon: "calendar.fill",
                label: "Last Activity",
                value: formatDate(session.lastActivity)
            )
        }
    }

    private func preferencesSection(session: UserSessionState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences")
                .font(.headline)

            PreferenceToggle(
                icon: "bell.fill",
                label: "Notifications",
                isOn: session.preferences.notificationsEnabled,
                action: { store.dispatch(.userSession(.toggleNotifications)) }
            )

            PreferenceToggle(
                icon: "moon.fill",
                label: "Dark Mode",
                isOn: session.preferences.darkMode,
                action: { store.dispatch(.userSession(.toggleDarkMode)) }
            )

            PreferenceToggle(
                icon: "arrow.clockwise.circle.fill",
                label: "Auto Save",
                isOn: session.preferences.autoSave,
                action: { store.dispatch(.userSession(.toggleAutoSave)) }
            )
        }
    }

    private var logoutButton: some View {
        Button {
            store.dispatch(.logout)
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Logout")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red.opacity(0.1))
            .foregroundStyle(.red)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var loginPromptSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text("Please log in to continue")
                .font(.headline)

            Text("You need an active session to access preferences and features")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingLoginSheet = true
            } label: {
                HStack {
                    Image(systemName: "person.fill")
                    Text("Login")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 40)
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How .optional() Works:")
                .font(.headline)

            Group {
                Text("• Session stored as UserSessionState? (optional)")
                Text("• nil = logged out, non-nil = logged in")
                Text("• Actions: .userSession(.toggleNotifications)")
                Text("• .optional() only runs if session exists")
                Text("• Parent handles login (creates) & logout (removes)")
                Text("• Child reducer safely modifies when present")
            }
            .font(.caption)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

private struct InfoCard: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.body)
            }

            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PreferenceToggle: View {
    let icon: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isOn ? .blue : .gray)
                    .frame(width: 30)

                Text(label)
                    .font(.body)

                Spacer()

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? .green : .gray)
            }
            .padding()
            .background(isOn ? Color.green.opacity(0.05) : Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .foregroundStyle(.primary)
    }
}

private struct LoginSheet: View {
    @Environment(Store<OptionalExampleAppState, OptionalExampleAppAction>.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Information") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }

                Section {
                    Text("This is a demo login. Enter any username and email to create a session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Login") {
                        let finalUsername = username.isEmpty ? "Demo User" : username
                        let finalEmail = email.isEmpty ? "demo@example.com" : email
                        store.dispatch(.login(username: finalUsername, email: finalEmail))
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let store = Store(
        initialState: OptionalExampleAppState(),
        reducer: OptionalExampleAppReducer(),
        middlewares: []
    )

    return NavigationStack {
        OptionalExampleView()
            .environment(store)
    }
}

#Preview("Logged In") {
    let initialState = OptionalExampleAppState(
        userSession: UserSessionState(
            username: "john_doe",
            email: "john@example.com",
            loginTime: Date().addingTimeInterval(-300),
            lastActivity: Date(),
            preferences: UserSessionState.Preferences(
                notificationsEnabled: true,
                darkMode: false,
                autoSave: true
            )
        ),
        loginAttempts: 1
    )

    let store = Store(
        initialState: initialState,
        reducer: OptionalExampleAppReducer(),
        middlewares: []
    )

    return NavigationStack {
        OptionalExampleView()
            .environment(store)
    }
}

// MARK: - Key Takeaways

// 1. OPTIONAL REDUCER PURPOSE:
//   - Manages state that may or may not exist
//   - Only runs child reducer when state is present (not nil)
//   - Parent controls creation and removal of optional state
//
// 2. OPTIONAL STRUCTURE:
//   - Parent state contains Optional<ChildState>
//   - Parent actions include .childAction(ChildAction)
//   - Prism extracts child actions from parent actions
//   - .optional() wraps the child reducer
//
// 3. OPTIONAL USAGE:
//   - `.optional()` creates a reducer that:
//     * Works on Optional<ChildState>
//     * Only runs if state is not nil
//     * Returns unchanged nil if state is nil
//     * Returns updated Optional<ChildState> if state exists
//
// 4. BENEFITS:
//   - Safe handling of optional state
//   - No need for nil checks in child reducer
//   - Child reducer stays simple and focused
//   - Parent has full control over state lifecycle
//
// 5. COMMON USE CASES:
//   - User sessions (logged in/out)
//   - Active order/cart (present/empty)
//   - Editing state (editing/not editing)
//   - Modal/sheet content (shown/hidden)
//   - Selected item (selected/none)
//
// 6. EXAMPLE FLOW:
//   User logged in → session is UserSessionState
//   → Dispatches: .userSession(.toggleNotifications)
//   → Parent reducer sees action
//   → Optional reducer checks session is not nil
//   → UserSessionReducer toggles notifications
//   → State updates, UI re-renders
//
//   User logged out → session is nil
//   → Dispatches: .userSession(.toggleNotifications)
//   → Parent reducer sees action
//   → Optional reducer checks session is nil
//   → Returns state unchanged (no crash!)
//   → UI stays the same
//
// 7. PATTERN COMBINATION:
//   - Often combined with .lifted() as shown:
//     UserSessionReducer()
//       .optional()                          // Handle nil case
//       .lifted(keyPath:prism:)              // Embed in parent state
//
// 8. COMPARISON WITH OTHER PATTERNS:
//   - .lifted(): Single child state (always present)
//   - .keyed(): Multiple items in Dictionary
//   - .offset(): Multiple items in Array
//   - .optional(): Single child state (may be nil)
//
// 9. PARENT RESPONSIBILITIES:
//   - Create optional state (login action)
//   - Remove optional state (logout action)
//   - Route actions to child when present
//
// 10. CHILD RESPONSIBILITIES:
//   - Operate on guaranteed non-nil state
//   - Modify state properties
//   - No lifecycle management
