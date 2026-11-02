import Foundation
import ReduxKit
import ReduxKitExtensions
import SwiftUI

// MARK: - Filtered Keyed Example: User Management with Bulk Status Updates

// This example demonstrates how to use filteredKeyed to perform batch operations
// on filtered dictionary values. Perfect for scenarios like:
// - Updating all active users
// - Bulk status changes for specific user types
// - Batch operations on filtered keyed collections

// MARK: - User Model

/// A user in the system
struct User: Hashable, Identifiable {
    let id: UUID
    var name: String
    var status: Status
    var role: Role
    var lastActive: Date

    enum Status: String, Hashable, CaseIterable {
        case active = "Active"
        case inactive = "Inactive"
        case suspended = "Suspended"
    }

    enum Role: String, Hashable, CaseIterable {
        case admin = "Admin"
        case moderator = "Moderator"
        case user = "User"
    }
}

// MARK: - State

struct UserManagementState: Hashable {
    var users: [UUID: User] = [:]
    var bulkActionLog: [String] = []

    init() {
        let now = Date()
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let id4 = UUID()
        let id5 = UUID()
        let id6 = UUID()

        self.users = [
            id1: User(
                id: id1,
                name: "Alice Admin",
                status: .active,
                role: .admin,
                lastActive: now.addingTimeInterval(-3_600) // 1 hour ago
            ),
            id2: User(
                id: id2,
                name: "Bob Moderator",
                status: .active,
                role: .moderator,
                lastActive: now.addingTimeInterval(-7_200) // 2 hours ago
            ),
            id3: User(
                id: id3,
                name: "Charlie User",
                status: .inactive,
                role: .user,
                lastActive: now.addingTimeInterval(-86_400) // 1 day ago
            ),
            id4: User(
                id: id4,
                name: "Diana User",
                status: .active,
                role: .user,
                lastActive: now.addingTimeInterval(-1_800) // 30 minutes ago
            ),
            id5: User(
                id: id5,
                name: "Eve Moderator",
                status: .suspended,
                role: .moderator,
                lastActive: now.addingTimeInterval(-172_800) // 2 days ago
            ),
            id6: User(
                id: id6,
                name: "Frank User",
                status: .inactive,
                role: .user,
                lastActive: now.addingTimeInterval(-259_200) // 3 days ago
            )
        ]
    }
}

// MARK: - Actions

enum UserManagementAction: Actionable {
    case updateUser(UUID, UserItemAction)
    case bulkUpdateByStatus(User.Status, UserItemAction)
    case bulkUpdateByRole(User.Role, UserItemAction)
    case bulkUpdateActive(UserItemAction)
    case clearLog
}

enum UserItemAction: Actionable {
    case setStatus(User.Status)
    case suspend
    case activate
}

// MARK: - Reducer

struct UserItemReducer: Reducer {
    func reduce(oldState: User, with action: UserItemAction) -> User {
        var state = oldState
        switch action {
        case let .setStatus(status):
            state.status = status
        case .suspend:
            state.status = .suspended
        case .activate:
            state.status = .active
        }
        return state
    }
}

struct UserManagementReducer: Reducer {
    let userReducer = UserItemReducer()

    /// Create prism functions for different filter scenarios
    static func statusPrism(for status: User.Status) -> Prism<UserManagementAction, UserItemAction> {
        Prism<UserManagementAction, UserItemAction>(
            embed: { UserManagementAction.bulkUpdateByStatus(status, $0) },
            extract: { action in
                if case let .bulkUpdateByStatus(stat, userAction) = action, stat == status {
                    return userAction
                }
                return nil
            }
        )
    }

    static func rolePrism(for role: User.Role) -> Prism<UserManagementAction, UserItemAction> {
        Prism<UserManagementAction, UserItemAction>(
            embed: { UserManagementAction.bulkUpdateByRole(role, $0) },
            extract: { action in
                if case let .bulkUpdateByRole(rol, userAction) = action, rol == role {
                    return userAction
                }
                return nil
            }
        )
    }

    static let activePrism = Prism<UserManagementAction, UserItemAction>(
        embed: { UserManagementAction.bulkUpdateActive($0) },
        extract: { action in
            if case let .bulkUpdateActive(userAction) = action {
                return userAction
            }
            return nil
        }
    )

    func reduce(oldState: UserManagementState, with action: UserManagementAction) -> UserManagementState {
        var state = oldState

        switch action {
        case let .updateUser(id, userAction):
            if let user = state.users[id] {
                state.users[id] = userReducer.reduce(oldState: user, with: userAction)
            }

        case let .bulkUpdateByStatus(status, userAction):
            // Use filteredKeyed to update only users with the selected status
            let statusReducer = userReducer.filteredKeyed(
                keyPath: \UserManagementState.users,
                prism: Self.statusPrism(for: status),
                predicate: { user in user.status == status }
            )
            state = statusReducer.reduce(
                oldState: state,
                with: .bulkUpdateByStatus(status, userAction)
            )
            let actionDesc = describeAction(userAction)
            state.bulkActionLog.append("Bulk \(actionDesc) all \(status.rawValue) users")

        case let .bulkUpdateByRole(role, userAction):
            // Use filteredKeyed to update only users with the selected role
            let roleReducer = userReducer.filteredKeyed(
                keyPath: \UserManagementState.users,
                prism: Self.rolePrism(for: role),
                predicate: { user in user.role == role }
            )
            state = roleReducer.reduce(
                oldState: state,
                with: .bulkUpdateByRole(role, userAction)
            )
            let actionDesc = describeAction(userAction)
            state.bulkActionLog.append("Bulk \(actionDesc) all \(role.rawValue) users")

        case let .bulkUpdateActive(userAction):
            // Use filteredKeyed to update only active users
            let activeReducer = userReducer.filteredKeyed(
                keyPath: \UserManagementState.users,
                prism: Self.activePrism,
                predicate: { user in user.status == .active }
            )
            state = activeReducer.reduce(
                oldState: state,
                with: .bulkUpdateActive(userAction)
            )
            let actionDesc = describeAction(userAction)
            state.bulkActionLog.append("Bulk \(actionDesc) all active users")

        case .clearLog:
            state.bulkActionLog.removeAll()
        }

        return state
    }

    private func describeAction(_ action: UserItemAction) -> String {
        switch action {
        case let .setStatus(status): "set status to \(status.rawValue)"
        case .suspend: "suspended"
        case .activate: "activated"
        }
    }
}

// MARK: - View

struct FilteredKeyedExampleView: View {
    @State private var store = Store(
        initialState: UserManagementState(),
        reducer: UserManagementReducer(),
        middlewares: []
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                Divider()

                // Bulk Actions
                bulkActionsSection

                Divider()

                // User List
                userListSection

                Divider()

                // Action Log
                actionLogSection
            }
            .padding()
        }
        .navigationTitle("Filtered Keyed Example")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)

            Text("FilteredKeyed Reducer")
                .font(.title2)
                .fontWeight(.bold)

            Text("Batch operations on filtered dictionary values")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var bulkActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bulk Actions")
                .font(.headline)

            // Status-based actions
            VStack(alignment: .leading, spacing: 8) {
                Text("By Status")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        store.dispatch(.bulkUpdateByStatus(.active, .suspend))
                    } label: {
                        Label("Suspend Active", systemImage: "pause.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button {
                        store.dispatch(.bulkUpdateByStatus(.inactive, .activate))
                    } label: {
                        Label("Activate Inactive", systemImage: "play.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
            }

            // Role-based actions
            VStack(alignment: .leading, spacing: 8) {
                Text("By Role")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(User.Role.allCases, id: \.self) { role in
                            Button {
                                store.dispatch(.bulkUpdateByRole(role, .suspend))
                            } label: {
                                Text("Suspend \(role.rawValue)s")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(roleColor(role))
                        }
                    }
                }
            }

            // Active users action
            VStack(alignment: .leading, spacing: 8) {
                Text("Active Users")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    store.dispatch(.bulkUpdateActive(.setStatus(.inactive)))
                } label: {
                    Label("Deactivate All", systemImage: "person.crop.circle.badge.xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var userListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Users (\(store.users.count))")
                .font(.headline)

            let sortedUsers = store.users.values.sorted { $0.name < $1.name }
            ForEach(sortedUsers) { user in
                UserRow(user: user)
            }
        }
    }

    private var actionLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Action Log")
                    .font(.headline)

                Spacer()

                if !store.bulkActionLog.isEmpty {
                    Button {
                        store.dispatch(.clearLog)
                    } label: {
                        Text("Clear")
                            .font(.caption)
                    }
                }
            }

            if store.bulkActionLog.isEmpty {
                Text("No actions yet. Try using bulk actions above!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.bulkActionLog.reversed(), id: \.self) { log in
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(log)
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func roleColor(_ role: User.Role) -> Color {
        switch role {
        case .admin: .purple
        case .moderator: .blue
        case .user: .gray
        }
    }
}

// MARK: - Supporting Views

private struct UserRow: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor(user.status))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Label(user.role.rawValue, systemImage: roleIcon(user.role))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(user.status.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(user.status).opacity(0.2))
                        .foregroundStyle(statusColor(user.status))
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusColor(_ status: User.Status) -> Color {
        switch status {
        case .active: .green
        case .inactive: .gray
        case .suspended: .red
        }
    }

    private func roleIcon(_ role: User.Role) -> String {
        switch role {
        case .admin: "star.fill"
        case .moderator: "shield.fill"
        case .user: "person.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FilteredKeyedExampleView()
    }
}
