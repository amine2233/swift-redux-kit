---
name: best-practice-list
description: Best practices for implementing a list screen in ReduxKit, covering state management with lifted row reducers, efficient data structures for large lists, and SwiftUI integration for dynamic row content and interactions.
---

# List with Lifted Row

A list screen owns the parent store.
Each row can be a simple value view or a stateful view whose sub-state is lifted into the parent store via a `RowReducer` and an ID-keyed `Prism`.

## When to Use Which Pattern

| Row needs | Approach |
|-----------|----------|
| Display only, tap to navigate | Simple value row — pass `item`, use parent store for navigation |
| UI-only toggle (ephemeral, lost on reload) | `@State` inside the row view |
| State that survives list reloads or affects parent logic | Lifted row — `RowReducer` keyed by `Item.ID` in parent store |

---

## 1. Simple Row (Most Common)

The row is a pure view. All interactions dispatch directly to the parent store.

```swift
// ItemRowView.swift — no store, no state
struct ItemRowView: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading) {
            Text(item.name).font(.headline)
            Text(item.subtitle).foregroundStyle(.secondary)
        }
    }
}

// Parent list view
List(store.items) { item in
    ItemRowView(item: item)
        .onTapGesture {
            navigationStore.dispatch(.push(.detail(id: item.id)))
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.dispatch(.confirmDelete(item))
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
}
```

---

## 2. Row with Ephemeral Local State

Use `@State` for UI-only toggles that don't need to survive list reloads.

```swift
struct ItemRowView: View {
    let item: Item
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(item.name).font(.headline)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            }
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }

            if isExpanded {
                Text(item.description)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: isExpanded)
    }
}
```

---

## 3. Lifted Row — RowReducer Keyed by Item ID

Use this when row state must survive list reloads (e.g., selection, inline editing, per-row loading indicator) or when parent logic depends on it.

### 3.1 RowReducer

Self-contained. Knows nothing about the parent.

```swift
// ItemRowReducer.swift
struct ItemRowReducer: Reducer {
    struct State: Hashable {
        var isExpanded: Bool = false
        var isEditing: Bool = false
    }

    enum Action: Actionable {
        case toggleExpanded
        case setEditing(Bool)
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .toggleExpanded:
            state.isExpanded.toggle()
        case let .setEditing(value):
            state.isEditing = value
        }
        return state
    }
}
```

### 3.2 Parent State & Action

Embed a dictionary of row states keyed by `Item.ID`.

```swift
// AppReducer.swift
struct AppReducer: Reducer {
    struct State: Hashable {
        var items: [Item] = []
        var isLoaded: LoadingState = .loaded
        // Row states keyed by item ID — initialised lazily when items load
        var rowStates: [Item.ID: ItemRowReducer.State] = [:]
    }

    enum Action: Actionable {
        case load
        case loaded(items: [Item])
        case failure(failure: State.MessageError)
        // Carries the target item ID and the row-level action
        case row(id: Item.ID, action: ItemRowReducer.Action)
    }
}
```

### 3.3 Prism — Extract (ID, RowAction) from AppAction

Define the prism as a `static var` on `AppAction`. It extracts the `(Item.ID, ItemRowReducer.Action)` pair that `.keyed()` needs.

```swift
extension AppReducer.Action {
    static var rowPrism: Prism<AppReducer.Action, (Item.ID, ItemRowReducer.Action)> {
        .init(
            embed: { AppReducer.Action.row(id: $0.0, action: $0.1) },
            extract: {
                guard case let .row(id, action) = $0 else { return nil }
                return (id, action)
            }
        )
    }
}
```

### 3.4 Parent Reducer — Use `.keyed()` for Row Actions

Handle parent-level cases in the switch, then delegate all `.row` actions to `ItemRowReducer` via `.keyed()`. The keyed reducer is a no-op for any action whose prism returns `nil`.

```swift
extension AppReducer {
    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState

        switch action {
        case .load:
            state.isLoaded = .loading

        case let .loaded(items):
            state.items = items
            state.isLoaded = .loaded
            // Seed missing row states without overwriting existing ones
            for item in items where state.rowStates[item.id] == nil {
                state.rowStates[item.id] = .init()
            }

        case let .failure(failure):
            state.messageError = failure
            state.isLoaded = .loaded

        case .row:
            break   // handled by the keyed reducer below
        }

        // Delegate row actions to ItemRowReducer via .keyed()
        return ItemRowReducer()
            .keyed(keyPath: \.rowStates, prism: Action.rowPrism)
            .reduce(oldState: state, with: action)
    }
}
```

`.keyed()` automatically:

1. Extracts `(id, rowAction)` using the prism.
2. Looks up `rowStates[id]` — silently skips if the key is absent.
3. Applies `ItemRowReducer` and writes the result back to `rowStates[id]`.

### 3.5 Row View — Reads Parent Store via @Environment

The row reads its slice of state from the shared parent store using its `item.id` as a key.

```swift
// ItemRowView.swift
@MainActor
struct ItemRowView: View {
    let item: Item
    @Environment(\.store) private var store

    // Convenience accessor — falls back to a default state if missing
    private var rowState: ItemRowReducer.State {
        store.rowStates[item.id] ?? .init()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(item.name).font(.headline)
                    Text(item.subtitle).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: rowState.isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                store.dispatch(.row(id: item.id, action: .toggleExpanded))
            }

            if rowState.isExpanded {
                Text(item.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.default, value: rowState.isExpanded)
    }
}
```

### 3.6 Parent List View

The parent list passes only the item value. The row handles its own store access.

```swift
@MainActor
struct ItemListView: View {
    @State private var navigationStore = NavigationStore.shared
    @Environment(\.store) private var store

    var body: some View {
        List(store.items) { item in
            ItemRowView(item: item)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.dispatch(.confirmDelete(item))
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
        .task { await store.send(.load) }
    }
}
```

---

## Data Flow

```
User taps row
      │
      ▼
store.dispatch(.row(id: item.id, action: .toggleExpanded))
      │
      ▼ synchronous (reducer)
AppReducer.reduce → case .row: break
      │
      ▼
ItemRowReducer().keyed(keyPath: \.rowStates, prism: .rowPrism)
    prism extracts (item.id, .toggleExpanded)
    rowStates[item.id] = ItemRowReducer().reduce(current, .toggleExpanded)
      │
      ▼
SwiftUI re-renders only ItemRowView(item.id) via @Observable
```

The middleware is never involved — row interactions are pure reducer mutations with no side effects.

---

## Previews

```swift
#Preview("Expanded Row") {
    List {
        ItemRowView(item: .preview)
    }
    .setEnvironmentStore(
        AppStore(
            initialState: AppReducer.State(
                items: [.preview],
                rowStates: [Item.preview.id: .init(isExpanded: true)]
            ),
            reducer: AppReducer(),
            middlewares: []
        )
    )
}

#Preview("Collapsed Row") {
    List {
        ItemRowView(item: .preview)
    }
    .setEnvironmentStore(
        AppStore(
            initialState: AppReducer.State(
                items: [.preview],
                rowStates: [Item.preview.id: .init(isExpanded: false)]
            ),
            reducer: AppReducer(),
            middlewares: []
        )
    )
}
```
