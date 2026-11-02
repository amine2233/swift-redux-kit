import Foundation
import ReduxKit
import ReduxKitExtensions
import SwiftUI

// MARK: - Sorted Offset Example: Leaderboard with Auto-Sorting

// This example demonstrates how to use comparableOffset to maintain a sorted list
// that automatically re-sorts after updates. Perfect for scenarios like:
// - Leaderboards that update scores
// - Priority-based task lists
// - Any list that needs to maintain sort order after modifications

// MARK: - Player Model

/// A player in the leaderboard
struct Player: Hashable, Identifiable {
    let id: UUID
    var name: String
    var score: Int
    var level: Int
    var isOnline: Bool
}

// MARK: - State

struct LeaderboardState: Hashable {
    var players: [Player] = []
    var sortMode: SortMode = .score
    var updateLog: [String] = []

    enum SortMode: String, Hashable, CaseIterable {
        case score = "Score"
        case level = "Level"
        case name = "Name"
    }

    init() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let id4 = UUID()
        let id5 = UUID()

        self.players = [
            Player(id: id1, name: "Alice", score: 1_500, level: 15, isOnline: true),
            Player(id: id2, name: "Bob", score: 2_100, level: 18, isOnline: true),
            Player(id: id3, name: "Charlie", score: 1_800, level: 16, isOnline: false),
            Player(id: id4, name: "Diana", score: 2_500, level: 20, isOnline: true),
            Player(id: id5, name: "Eve", score: 1_200, level: 12, isOnline: false)
        ]
    }

    func comparator(for mode: SortMode) -> (Player, Player) -> Bool {
        switch mode {
        case .score:
            { $0.score > $1.score } // Descending
        case .level:
            { $0.level > $1.level } // Descending
        case .name:
            { $0.name < $1.name } // Ascending
        }
    }
}

// MARK: - Actions

enum LeaderboardAction: Actionable {
    case updatePlayer(Int, PlayerAction)
    case setSortMode(LeaderboardState.SortMode)
    case clearLog
}

enum PlayerAction: Actionable {
    case addPoints(Int)
    case subtractPoints(Int)
    case levelUp
    case toggleOnline
}

// MARK: - Reducer

struct PlayerReducer: Reducer {
    func reduce(oldState: Player, with action: PlayerAction) -> Player {
        var state = oldState
        switch action {
        case let .addPoints(points):
            state.score += points
        case let .subtractPoints(points):
            state.score = max(0, state.score - points)
        case .levelUp:
            state.level += 1
        case .toggleOnline:
            state.isOnline.toggle()
        }
        return state
    }
}

struct LeaderboardReducer: Reducer {
    let playerReducer = PlayerReducer()

    static let playerPrism = Prism<LeaderboardAction, (Int, PlayerAction)>(
        embed: { LeaderboardAction.updatePlayer($0, $1) },
        extract: { action in
            if case let .updatePlayer(index, playerAction) = action {
                return (index, playerAction)
            }
            return nil
        }
    )

    func reduce(oldState: LeaderboardState, with action: LeaderboardAction) -> LeaderboardState {
        var state = oldState

        switch action {
        case let .updatePlayer(index, playerAction):
            // Use comparableOffset to update and auto-sort
            let sortedReducer = playerReducer.sortedOffset(
                keyPath: \LeaderboardState.players,
                prism: Self.playerPrism,
                comparator: state.comparator(for: state.sortMode)
            )

            if state.players.indices.contains(index) {
                let player = state.players[index]
                state = sortedReducer.reduce(
                    oldState: state,
                    with: .updatePlayer(index, playerAction)
                )
                state.updateLog.append(describeUpdate(player: player, action: playerAction))
            }

        case let .setSortMode(mode):
            state.sortMode = mode
            // Re-sort with new comparator
            state.players.sort(by: state.comparator(for: mode))
            state.updateLog.append("Changed sort mode to \(mode.rawValue)")

        case .clearLog:
            state.updateLog.removeAll()
        }

        return state
    }

    private func describeUpdate(player: Player, action: PlayerAction) -> String {
        switch action {
        case let .addPoints(points):
            "\(player.name) gained \(points) points"
        case let .subtractPoints(points):
            "\(player.name) lost \(points) points"
        case .levelUp:
            "\(player.name) leveled up to \(player.level + 1)"
        case .toggleOnline:
            "\(player.name) went \(player.isOnline ? "offline" : "online")"
        }
    }
}

// MARK: - View

struct SortedOffsetExampleView: View {
    @State private var store = Store(
        initialState: LeaderboardState(),
        reducer: LeaderboardReducer(),
        middlewares: []
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                Divider()

                // Sort Controls
                sortControlsSection

                Divider()

                // Leaderboard
                leaderboardSection

                Divider()

                // Update Log
                updateLogSection
            }
            .padding()
        }
        .navigationTitle("Sorted Offset Example")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 50))
                .foregroundStyle(.purple)

            Text("SortedOffset Reducer")
                .font(.title2)
                .fontWeight(.bold)

            Text("Auto-sorting leaderboard")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var sortControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sort By")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(LeaderboardState.SortMode.allCases, id: \.self) { mode in
                    Button {
                        store.dispatch(.setSortMode(mode))
                    } label: {
                        Text(mode.rawValue)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                store.sortMode == mode
                                    ? Color.purple
                                    : Color.purple.opacity(0.2)
                            )
                            .foregroundStyle(
                                store.sortMode == mode
                                    ? .white
                                    : .purple
                            )
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboard")
                .font(.headline)

            ForEach(Array(store.players.enumerated()), id: \.element.id) { index, player in
                PlayerRow(
                    player: player,
                    rank: index + 1,
                    onAddPoints: {
                        store.dispatch(.updatePlayer(index, .addPoints(100)))
                    },
                    onLevelUp: {
                        store.dispatch(.updatePlayer(index, .levelUp))
                    },
                    onToggleOnline: {
                        store.dispatch(.updatePlayer(index, .toggleOnline))
                    }
                )
            }
        }
    }

    private var updateLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Update Log")
                    .font(.headline)

                Spacer()

                if !store.updateLog.isEmpty {
                    Button {
                        store.dispatch(.clearLog)
                    } label: {
                        Text("Clear")
                            .font(.caption)
                    }
                }
            }

            if store.updateLog.isEmpty {
                Text("No updates yet. Try updating player stats above!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.updateLog.reversed(), id: \.self) { log in
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
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
}

// MARK: - Supporting Views

private struct PlayerRow: View {
    let player: Player
    let rank: Int
    let onAddPoints: () -> Void
    let onLevelUp: () -> Void
    let onToggleOnline: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Player info
            HStack(spacing: 12) {
                // Rank badge
                Text("#\(rank)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(rankColor(rank))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(player.name)
                            .font(.body)
                            .fontWeight(.semibold)

                        Circle()
                            .fill(player.isOnline ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                    }

                    HStack(spacing: 12) {
                        Label("\(player.score)", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Label("Lvl \(player.level)", systemImage: "shield.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    onAddPoints()
                } label: {
                    Label("+100", systemImage: "plus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Button {
                    onLevelUp()
                } label: {
                    Label("Level Up", systemImage: "arrow.up.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Button {
                    onToggleOnline()
                } label: {
                    Label(
                        player.isOnline ? "Go Offline" : "Go Online",
                        systemImage: "network"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: .yellow
        case 2: .gray
        case 3: .orange
        default: .purple
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SortedOffsetExampleView()
    }
}
