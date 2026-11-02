import ReduxKit
import ReduxKitExtensions
import SwiftUI

/// Root app view that handles navigation and app state
struct AppView: View {
    @Environment(Store<AppStore.State, AppStore.Action>.self) private var store
    @Environment(Store<NavigationStore.State, NavigationStore.Action>.self) private var navigationStore

    var body: some View {
        ZStack {
            if store.isLoading {
                SplashScreen()
            } else {
                NavigationStack(path: navigationStore.binding(\.path, send: { .setPath($0) })) {
                    MainView()
                        .navigationDestination(for: NavigationStore.Destination.self) { destination in
                            destinationView(for: destination)
                        }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.isLoading)
        .onAppear {
            store.dispatch(.appLaunched)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: NavigationStore.Destination) -> some View {
        switch destination {
        case .main:
            MainView()

        case .prismExample:
            let exampleStore = Store(
                initialState: ExampleAppState(),
                reducer: ExampleAppReducer(),
                middlewares: []
            )
            PrismExampleView()
                .environment(exampleStore)

        case .keyedExample:
            let initialState = TodoListState(
                todos: [
                    UUID(1): TodoItemState(
                        id: UUID(1),
                        title: "Learn ReduxKit",
                        isCompleted: false,
                        priority: .high
                    ),
                    UUID(2): TodoItemState(
                        id: UUID(2),
                        title: "Understand Prism",
                        isCompleted: true,
                        priority: .medium
                    ),
                    UUID(3): TodoItemState(
                        id: UUID(3),
                        title: "Master .keyed()",
                        isCompleted: false,
                        priority: .medium
                    )
                ]
            )
            let todoStore = Store(
                initialState: initialState,
                reducer: TodoListReducer(),
                middlewares: []
            )
            KeyedExampleView()
                .environment(todoStore)

        case .offsetExample:
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
            let playlistStore = Store(
                initialState: initialState,
                reducer: PlaylistReducer(),
                middlewares: []
            )
            OffsetExampleView()
                .environment(playlistStore)

        case .filterOffsetExample:
            FilterOffsetExampleView()

        case .filteredKeyedExample:
            FilteredKeyedExampleView()

        case .sortedOffsetExample:
            SortedOffsetExampleView()

        case .optionalExample:
            let optionalStore = Store(
                initialState: OptionalExampleAppState(),
                reducer: OptionalExampleAppReducer(),
                middlewares: []
            )
            OptionalExampleView()
                .environment(optionalStore)

        case .undoableExample:
            UndoableExampleView()

        case .descriptiveUndoableExample:
            DescriptiveUndoableExampleView()

        case .actionableUndoableExample:
            ActionableUndoableExampleView()

        case .serviceExample:
            ServiceExampleView()
        }
    }
}

#Preview("Loading") {
    AppView()
        .environment(AppStore.shared)
        .environment(NavigationStore.shared)
}

#Preview("Loaded") {
    AppStore.shared.dispatch(.finishLoading)

    return AppView()
        .environment(AppStore.shared)
        .environment(NavigationStore.shared)
}
