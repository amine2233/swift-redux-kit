import Foundation
import ReduxKit
import ReduxKitExtensions
import SwiftUI

// MARK: - Offset Reducer Example: Managing Array Collections

// This example demonstrates how to use .offset() to manage a collection of items in an array,
// where each item has its own state and reducer.
//
// The problem:
// - You have an ordered collection of items (e.g., playlist tracks, shopping list, game levels)
// - Each item needs its own independent state
// - Items are stored in an Array (order matters)
// - Parent needs to route actions to specific items by index
//
// The solution:
// - Store items in an Array<ItemState>
// - Use Prism to extract (Index, ItemAction) tuples from parent actions
// - Use .offset() to lift the child reducer to work on the array
// - The offset reducer applies child reducer to the item at the given index

// MARK: - Child Feature: Playlist Track

/// Individual track state
struct PlaylistTrackState: Sendable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var artist: String
    var duration: TimeInterval
    var isPlaying: Bool
    var isFavorite: Bool

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Actions for individual tracks
enum PlaylistTrackAction: Actionable {
    case play
    case pause
    case toggleFavorite
    case updateTitle(String)
    case updateArtist(String)
}

/// Reducer for a single track
struct PlaylistTrackReducer: Reducer {
    func reduce(oldState: PlaylistTrackState, with action: PlaylistTrackAction) -> PlaylistTrackState {
        var state = oldState

        switch action {
        case .play:
            state.isPlaying = true

        case .pause:
            state.isPlaying = false

        case .toggleFavorite:
            state.isFavorite.toggle()

        case let .updateTitle(title):
            state.title = title

        case let .updateArtist(artist):
            state.artist = artist
        }

        return state
    }
}

// MARK: - Parent: Playlist State & Actions

/// Parent state containing ordered tracks in an array
struct PlaylistState: Sendable, Hashable {
    var tracks: [PlaylistTrackState] = []
    var playlistName: String = "My Playlist"
    var currentlyPlayingIndex: Int?

    var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    var formattedTotalDuration: String {
        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var favoritesCount: Int {
        tracks.filter { $0.isFavorite }.count
    }
}

/// Parent actions - includes offset child actions
enum PlaylistAction: Actionable {
    case addTrack(PlaylistTrackState)
    case removeTrack(at: Int)
    case moveTrack(from: Int, to: Int)
    case playTrack(at: Int)
    case stopAllTracks
    case updatePlaylistName(String)
    case track(at: Int, action: PlaylistTrackAction) // Offset action: (Index, Child Action)
}

// MARK: - Prism for Offset Actions

extension Prism where Source == PlaylistAction, Target == (Int, PlaylistTrackAction) {
    /// Prism that extracts (Index, PlaylistTrackAction) tuples from PlaylistAction
    static var track: Prism<PlaylistAction, (Int, PlaylistTrackAction)> {
        Prism(
            // embed: Wrap (Index, Action) tuple into parent action
            embed: { tuple in
                .track(at: tuple.0, action: tuple.1)
            },
            // extract: Extract (Index, Action) tuple from parent action
            extract: { parentAction in
                guard case let .track(index, action) = parentAction else {
                    return nil
                }

                return (index, action)
            }
        )
    }
}

// MARK: - Parent Reducer with Offset Child

struct PlaylistReducer: Reducer {
    func reduce(oldState: PlaylistState, with action: PlaylistAction) -> PlaylistState {
        var state = oldState

        // Handle parent-level actions
        switch action {
        case let .addTrack(track):
            state.tracks.append(track)

        case let .removeTrack(index):
            guard state.tracks.indices.contains(index) else { return state }

            state.tracks.remove(at: index)
            // Update currently playing index if needed
            if let currentIndex = state.currentlyPlayingIndex {
                if currentIndex == index {
                    state.currentlyPlayingIndex = nil
                } else if currentIndex > index {
                    state.currentlyPlayingIndex = currentIndex - 1
                }
            }

        case let .moveTrack(fromIndex, toIndex):
            guard state.tracks.indices.contains(fromIndex),
                  state.tracks.indices.contains(toIndex) else {
                return state
            }

            let track = state.tracks.remove(at: fromIndex)
            state.tracks.insert(track, at: toIndex)
            // Update currently playing index if needed
            if let currentIndex = state.currentlyPlayingIndex {
                if currentIndex == fromIndex {
                    state.currentlyPlayingIndex = toIndex
                } else if currentIndex == toIndex, fromIndex < toIndex {
                    state.currentlyPlayingIndex = toIndex - 1
                } else if currentIndex == toIndex, fromIndex > toIndex {
                    state.currentlyPlayingIndex = toIndex + 1
                }
            }

        case let .playTrack(index):
            guard state.tracks.indices.contains(index) else { return state }

            // Stop all other tracks
            state.tracks = state.tracks.map { track in
                var updated = track
                updated.isPlaying = false
                return updated
            }
            // Play the selected track
            state.tracks[index].isPlaying = true
            state.currentlyPlayingIndex = index

        case .stopAllTracks:
            state.tracks = state.tracks.map { track in
                var updated = track
                updated.isPlaying = false
                return updated
            }
            state.currentlyPlayingIndex = nil

        case let .updatePlaylistName(name):
            state.playlistName = name

        case .track:
            // Don't handle here - let the offset reducer handle it
            break
        }

        // Apply the offset child reducer using Prism
        // It will only modify the track at the specified index
        let offsetReducer = PlaylistTrackReducer().offset(
            keyPath: \PlaylistState.tracks, // Where the array lives
            prism: .track // How to extract (Index, Action) tuples
        )
        state = offsetReducer.reduce(oldState: state, with: action)

        return state
    }
}

// MARK: - SwiftUI Example View

struct OffsetExampleView: View {
    @Environment(Store<PlaylistState, PlaylistAction>.self) private var store
    @State private var showingAddSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Playlist Header
                playlistHeaderSection

                Divider()

                // Statistics
                statsSection

                Divider()

                // Track List
                trackListSection

                // Add Track Button
                addTrackButton

                // Explanation
                explanationSection
            }
            .padding()
        }
        .navigationTitle("Offset Example: Playlist")
        .sheet(isPresented: $showingAddSheet) {
            AddTrackSheet()
        }
    }

    // MARK: - Sections

    private var playlistHeaderSection: some View {
        VStack(spacing: 8) {
            TextField("Playlist Name", text: Binding(
                get: { store.playlistName },
                set: { store.dispatch(.updatePlaylistName($0)) }
            ))
            .font(.title2)
            .bold()
            .multilineTextAlignment(.center)
            .textFieldStyle(.plain)

            Text("\(store.tracks.count) tracks • \(store.formattedTotalDuration)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statsSection: some View {
        HStack(spacing: 20) {
            StatBadge(
                icon: "music.note.list",
                label: "Tracks",
                value: "\(store.tracks.count)",
                color: .blue
            )

            StatBadge(
                icon: "heart.fill",
                label: "Favorites",
                value: "\(store.favoritesCount)",
                color: .pink
            )

            StatBadge(
                icon: "clock.fill",
                label: "Duration",
                value: store.formattedTotalDuration,
                color: .green
            )
        }
    }

    private var trackListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tracks")
                    .font(.headline)

                Spacer()

                if store.currentlyPlayingIndex != nil {
                    Button {
                        store.dispatch(.stopAllTracks)
                    } label: {
                        Label("Stop All", systemImage: "stop.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(.red)
                }
            }

            if store.tracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)

                    Text("No tracks in playlist")
                        .foregroundStyle(.secondary)

                    Text("Tap the + button to add tracks")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(Array(store.tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, index: index)
                }
            }
        }
    }

    private var addTrackButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add Track")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(0.1))
            .foregroundStyle(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How .offset() Works:")
                .font(.headline)

            Group {
                Text("• Tracks stored in Array<PlaylistTrackState>")
                Text("• Each track managed by PlaylistTrackReducer")
                Text("• Actions: .track(at: 2, action: .play)")
                Text("• Prism extracts (Index, Action) tuple")
                Text("• .offset() applies reducer to tracks[index]")
                Text("• Parent handles add/remove/reorder")
                Text("• Order matters! Perfect for playlists, queues")
            }
            .font(.caption)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Supporting Views

private struct StatBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.headline)
                .bold()

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TrackRow: View {
    @Environment(Store<PlaylistState, PlaylistAction>.self) private var store
    let track: PlaylistTrackState
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            // Track number
            Text("\(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            // Play/Pause button
            Button {
                if track.isPlaying {
                    store.dispatch(.track(at: index, action: .pause))
                } else {
                    store.dispatch(.playTrack(at: index))
                }
            } label: {
                Image(systemName: track.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(track.isPlaying ? .green : .blue)
            }

            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(track.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Favorite button
            Button {
                store.dispatch(.track(at: index, action: .toggleFavorite))
            } label: {
                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(track.isFavorite ? .pink : .gray)
            }

            // Delete button
            Button {
                store.dispatch(.removeTrack(at: index))
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(track.isPlaying ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AddTrackSheet: View {
    @Environment(Store<PlaylistState, PlaylistAction>.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var artist = ""
    @State private var minutes = 3
    @State private var seconds = 30

    var body: some View {
        NavigationStack {
            Form {
                Section("Track Information") {
                    TextField("Title", text: $title)
                    TextField("Artist", text: $artist)
                }

                Section("Duration") {
                    Picker("Minutes", selection: $minutes) {
                        ForEach(0 ..< 10) { min in
                            Text("\(min)").tag(min)
                        }
                    }

                    Picker("Seconds", selection: $seconds) {
                        ForEach(0 ..< 60) { sec in
                            Text("\(sec)").tag(sec)
                        }
                    }
                }
            }
            .navigationTitle("Add Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let track = PlaylistTrackState(
                            id: UUID(),
                            title: title.isEmpty ? "Untitled" : title,
                            artist: artist.isEmpty ? "Unknown Artist" : artist,
                            duration: TimeInterval(minutes * 60 + seconds),
                            isPlaying: false,
                            isFavorite: false
                        )
                        store.dispatch(.addTrack(track))
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let initialState = PlaylistState(
        tracks: [
            PlaylistTrackState(
                id: UUID(1),
                title: "Bohemian Rhapsody",
                artist: "Queen",
                duration: 354,
                isPlaying: false,
                isFavorite: true
            ),
            PlaylistTrackState(
                id: UUID(2),
                title: "Stairway to Heaven",
                artist: "Led Zeppelin",
                duration: 482,
                isPlaying: false,
                isFavorite: true
            ),
            PlaylistTrackState(
                id: UUID(3),
                title: "Hotel California",
                artist: "Eagles",
                duration: 391,
                isPlaying: false,
                isFavorite: false
            )
        ],
        playlistName: "Classic Rock Hits"
    )

    let store = Store(
        initialState: initialState,
        reducer: PlaylistReducer(),
        middlewares: []
    )

    return NavigationStack {
        OffsetExampleView()
            .environment(store)
    }
}

// MARK: - Key Takeaways

// 1. OFFSET REDUCER PURPOSE:
//   - Manages collections of items stored in Array<ItemState>
//   - Routes actions to specific items by their index
//   - Applies child reducer to individual items
//   - Order matters (unlike .keyed() which uses Dictionary)
//
// 2. OFFSET STRUCTURE:
//   - Parent state contains Array<ChildState>
//   - Parent actions include .childAction(at: Index, action: ChildAction)
//   - Prism extracts (Index, ChildAction) tuples
//
// 3. OFFSET USAGE:
//   - `.offset(keyPath:prism:)` creates a reducer that:
//     * Works on parent state containing an array
//     * Extracts (Index, Action) from parent action using prism
//     * Applies child reducer to array[index]
//     * Returns updated parent state
//
// 4. BENEFITS:
//   - Each item independently managed by same reducer
//   - Type-safe routing of actions by index
//   - Maintains insertion order (important for playlists, queues)
//   - Clean separation: parent handles collection, child handles item
//
// 5. WHEN TO USE .offset() vs .keyed():
//   - Use .offset() when:
//     * Order matters (playlists, shopping lists, game levels)
//     * Items stored in Array
//     * Actions reference items by index
//
//   - Use .keyed() when:
//     * Order doesn't matter (users, settings, cache)
//     * Items stored in Dictionary
//     * Actions reference items by ID/key
//     * Need O(1) lookups by key
//
// 6. COMMON USE CASES:
//   - Music playlists (order matters)
//   - Shopping lists (order matters)
//   - Game levels (sequential order)
//   - Queue systems (FIFO order)
//   - Tutorial steps (sequential)
//
// 7. EXAMPLE FLOW:
//   User clicks play on track at index 2
//   → Dispatches: .track(at: 2, action: .play)
//   → Parent reducer sees action
//   → Offset reducer's prism extracts (2, .play)
//   → PlaylistTrackReducer sets tracks[2].isPlaying = true
//   → State updates, UI re-renders
//
// 8. INDEX SAFETY:
//   - Offset reducer checks if index is valid
//   - Returns unchanged state if index out of bounds
//   - Parent should validate indices before dispatching
