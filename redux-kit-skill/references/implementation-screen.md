---
name: implementation-screen
description: Guide to implementing a complete ReduxKit screen, covering State, Action, Reducer, Middleware, Store, and SwiftUI integration with best practices for loading states, error handling, and user interactions.
---

# Screen Implementation

A screen loads data on appear, manages a list with delete confirmation, and surfaces API/DB errors in an alert with an optional retry.

## Rules

1. **`@Environment` store for app-level screens** — screens that are part of the main app flow read the shared store from `@Environment(\.store) private var store`.
2. **Local store for self-contained screens** Self-contained screens and forms create their own store in `init` instead (see [implementation-form.md](implementation-form.md)).
3. **`.load` / `.loaded` pair** — every async data fetch starts with `.load` (sets `isLoaded = .loading`) and ends with `.loaded(data:)` (sets `isLoaded = .loaded`).
4. **Delete is a two-step action** — `.confirmDelete(item)` shows a confirmation dialog; only `.onDelete(item)` triggers the middleware.
5. **Failures become `State.MessageError`** — middleware catches all errors and returns `.failure(failure:)`. The reducer stores it; the view shows an alert.
6. **Retry dispatches `.load` again** — the error alert's Retry button is a free re-fetch.
7. **Middleware uses `Dependencies`** — never `@Dependency`. See [implementation-best-practice.md](implementation-best-practice.md).

---

## 1. State

```swift
struct MainReducer: Reducer {
    struct State: Hashable {
        // Loading lifecycle
        var isLoaded: LoadingState = .loaded

        // Data
        var items: [QRCodeModel] = []

        // Delete confirmation — set to the item pending deletion
        var deleteConfirmation: QRCodeModel? = nil

        // Error alert — set on any middleware failure
        var messageError: MessageError? = nil

        // Sheet navigation
        var sheet: Sheet? = nil

        enum Sheet: Identifiable, Hashable {
            var id: Self { self }
            case itemAdd
            case itemEdit(id: QRCodeModel.ID)
        }
    }
}

// LoadingState — shared across the app
enum LoadingState: Hashable {
    case loading
    case loaded
}

extension MainReducer.State {
    // Identifiable so .alert(item:) can bind directly
    struct MessageError: Hashable, Identifiable {
        let id: UUID = UUID()
        let title: String
        let message: String
        // Retry intent — true when the error is recoverable with .load
        let canRetry: Bool
    }
}
```

---

## 2. Actions

```swift
extension MainReducer {
    enum Action: Actionable {
        // Load lifecycle
        case load
        case loaded(items: [QRCodeModel])
        case failure(failure: State.MessageError)

        // CRUD
        case insert(QRCodeModel)
        case onDelete(QRCodeModel)       // triggers middleware
        case onDeleted(QRCodeModel)      // reducer removes item

        // Delete confirmation dialog
        case confirmDelete(QRCodeModel)  // shows the dialog
        case cancelDelete                // dismisses without deleting

        // Error alert
        case dismissError

        // Sheet
        case setSheet(State.Sheet?)
    }
}
```

---

## 3. Reducer

```swift
extension MainReducer {
    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        // --- Load lifecycle ---
        case .load:
            state.isLoaded = .loading

        case let .loaded(items):
            state.items = items
            state.isLoaded = .loaded

        case let .failure(failure):
            state.messageError = failure
            state.isLoaded = .loaded

        // --- CRUD ---
        case let .insert(item):
            state.items.append(item)

        case .onDelete:
            break // handled by middleware

        case let .onDeleted(item):
            state.items.removeAll { $0.id == item.id }

        // --- Delete confirmation ---
        case let .confirmDelete(item):
            state.deleteConfirmation = item

        case .cancelDelete:
            state.deleteConfirmation = nil

        // --- Error ---
        case .dismissError:
            state.messageError = nil

        // --- Sheet ---
        case let .setSheet(sheet):
            state.sheet = sheet
        }
        return state
    }
}
```

---

## 4. Middleware

Use a `Dependencies` struct so the middleware is testable without hitting the real DB/API.

```swift
final class MainMiddleware: Middleware, @unchecked Sendable {
    typealias Action = MainReducer.Action
    typealias State = MainReducer.State

    struct Dependencies {
        var fetchItems: () async throws -> [QRCodeModel]
        var insertItem: (QRCodeModel) async throws -> Void
        var deleteItem: (QRCodeModel.ID) async throws -> Void

        static var production: Dependencies {
            .init(
                fetchItems: {
                    try await QRCodeRepository.shared.fetchAll()
                },
                insertItem: { qrCode in
                    try await QRCodeRepository.shared.insert(qrCode)
                },
                deleteItem: { id in
                    try await QRCodeRepository.shared.delete(id: id)
                }
            )
        }
    }

    let dependencies: Dependencies

    init(dependencies: Dependencies = .production) {
        self.dependencies = dependencies
    }

    func process(state: State, with action: Action) async -> Action? {
        switch action {
        case .load:
            return await loadItems()
        case let .insert(item):
            return await insertItem(item)
        case let .onDelete(item):
            return await deleteItem(item)
        default:
            return nil
        }
    }

    private func loadItems() async -> Action {
        do {
            let items = try await dependencies.fetchItems()
            return .loaded(items: items)
        } catch {
            return .failure(failure: .init(
                title: "Failed to load",
                message: error.localizedDescription,
                canRetry: true
            ))
        }
    }

    private func insertItem(_ item: QRCodeModel) async -> Action? {
        do {
            try await dependencies.insertItem(item)
            return nil
        } catch {
            return .failure(failure: .init(
                title: "Failed to save",
                message: error.localizedDescription,
                canRetry: false
            ))
        }
    }

    private func deleteItem(_ item: QRCodeModel) async -> Action? {
        do {
            try await dependencies.deleteItem(item.id)
            return .onDeleted(item)
        } catch {
            return .failure(failure: .init(
                title: "Failed to delete",
                message: error.localizedDescription,
                canRetry: false
            ))
        }
    }
}
```

---

## 5. View

```swift
@MainActor
struct MainView: View {
    @State private var navigationStore = NavigationStore.shared
    @Environment(\.store) private var store

    var body: some View {
        NavigationStack(
            path: navigationStore.binding(\.homePaths, send: { .setHomePaths($0) })
        ) {
            content
                .navigationDestination(for: NavigationReducer.State.HomePath.self) { path in
                    switch path {
                    case let .detail(id): ItemDetailView(id: id)
                    }
                }
                // Sheet presentation
                .sheet(item: store.binding(\.sheet, send: { .setSheet($0) })) { sheet in
                    switch sheet {
                    case .itemAdd:
                        QRCodeEdit { completion in
                            switch completion {
                            case let .done(item):
                                if let item { store.dispatch(.insert(item)) }
                            case .cancel:
                                break
                            }
                        }
                    case let .itemEdit(id):
                        ItemEditView(id: id) { _ in }
                    }
                }
                // Delete confirmation dialog
                .confirmationDialog(
                    "Delete \(store.deleteConfirmation?.name ?? "")?",
                    isPresented: Binding(
                        get: { store.deleteConfirmation != nil },
                        set: { if !$0 { store.dispatch(.cancelDelete) } }
                    ),
                    titleVisibility: .visible
                ) {
                    if let item = store.deleteConfirmation {
                        Button("Delete", role: .destructive) {
                            store.dispatch(.onDelete(item))
                            store.dispatch(.cancelDelete)
                        }
                        Button("Cancel", role: .cancel) {
                            store.dispatch(.cancelDelete)
                        }
                    }
                }
                // Error alert with optional retry
                .alert(item: Binding(
                    get: { store.messageError },
                    set: { if $0 == nil { store.dispatch(.dismissError) } }
                )) { error in
                    Alert(
                        title: Text(error.title),
                        message: Text(error.message),
                        primaryButton: error.canRetry
                            ? .default(Text("Retry")) { store.dispatch(.load) }
                            : .default(Text("OK")) { store.dispatch(.dismissError) },
                        secondaryButton: error.canRetry
                            ? .cancel(Text("Cancel")) { store.dispatch(.dismissError) }
                            : .cancel(Text("Cancel")) { store.dispatch(.dismissError) }
                    )
                }
                // Load on appear
                .task { await store.send(.load) }
                .toolbar { if !store.items.isEmpty { toolbar } }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoaded == .loading {
            // Show placeholder skeleton while loading
            List(0..<6, id: \.self) { _ in
                ItemRowView(item: .placeholder)
                    .redacted(reason: .placeholder)
            }
        } else if store.items.isEmpty {
            // Empty state with CTA
            EmptyStateView(onAdd: { store.dispatch(.setSheet(.itemAdd)) })
        } else {
            List(store.items) { item in
                ItemRowView(item: item)
                    .onTapGesture {
                        navigationStore.dispatch(.setHomePaths([.detail(id: item.id)]))
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.dispatch(.confirmDelete(item))
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu { contextMenu(for: item) }
            }
        }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                store.dispatch(.setSheet(.itemAdd))
            } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }

    private func contextMenu(for item: QRCodeModel) -> some View {
        Group {
            Button {
                store.dispatch(.setSheet(.itemEdit(id: item.id)))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                store.dispatch(.confirmDelete(item))
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
```

Key points:

- `.task { await store.send(.load) }` — fires on appear and is automatically cancelled and restarted if the view is removed and re-added.
- The delete flow dispatches `.confirmDelete(item)` first — the middleware is only reached after the user confirms in the dialog.
- `.confirmationDialog(isPresented:)` uses a computed `Binding<Bool>` derived from `store.deleteConfirmation`. Dismissal dispatches `.cancelDelete`.
- `.alert(item:)` uses a computed `Binding<MessageError?>` derived from `store.messageError`. The Retry button re-dispatches `.load`; only shown when `canRetry == true`.

---

## 6. Previews

Use `.setEnvironmentStore()` to inject a pre-populated store without middleware — no network calls in previews.

```swift
// Empty state
#Preview("Empty") {
    NavigationStack {
        MainView()
    }
    .setEnvironmentStore(
        Store(
            initialState: MainReducer.State(items: []),
            reducer: MainReducer(),
            middlewares: []
        )
    )
}

// Populated list
#Preview("With items") {
    NavigationStack {
        MainView()
    }
    .setEnvironmentStore(
        Store(
            initialState: MainReducer.State(items: [.preview, .preview]),
            reducer: MainReducer(),
            middlewares: []
        )
    )
}

// Loading skeleton
#Preview("Loading") {
    NavigationStack {
        MainView()
    }
    .setEnvironmentStore(
        Store(
            initialState: MainReducer.State(items: [], isLoaded: .loading),
            reducer: MainReducer(),
            middlewares: []
        )
    )
}

// Error alert
#Preview("Error") {
    NavigationStack {
        MainView()
    }
    .setEnvironmentStore(
        Store(
            initialState: MainReducer.State(
                items: [],
                messageError: .init(
                    title: "Failed to load",
                    message: "No internet connection.",
                    canRetry: true
                )
            ),
            reducer: MainReducer(),
            middlewares: []
        )
    )
}
```
