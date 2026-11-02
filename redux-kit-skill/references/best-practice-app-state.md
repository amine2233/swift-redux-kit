---
name: best-practice-app-state
description: Best practices for app state design, including using TreeDictionary for efficient keyed storage and @CowBox for copy-on-write value semantics.
---

# App State Best Practices

Two optional but recommended additions for production app state: **`TreeDictionary`** for efficient keyed storage
and **`@CowBox`** for copy-on-write value semantics.

## Rules

1. **Prefer `TreeDictionary` over `[ID: Value]`** — `TreeDictionary` (from `swift-collections`) provides O(log n) lookup,
   insertion and deletion without full-array copies. Use it whenever the state holds a collection keyed by ID.
2. **Apply `@CowBox` to large state structs** — the macro wraps the struct in a copy-on-write box
   so that unchanged references share storage. This keeps `reduce` fast when only a small slice of state changes.
3. **Both are opt-in** — small features that hold a handful of items work fine with plain `[Item]` or `[ID: Value]`.
   Apply these only when profiling reveals a bottleneck or the collection is expected to grow large.

---

## 1. `TreeDictionary` — Efficient Keyed Storage

### Why

Swift's built-in `Dictionary` copies its entire internal hash table on every mutation inside a reducer (`var state = oldState`).
`TreeDictionary` from Apple's `swift-collections` package uses a persistent hash-array mapped trie (HAMT),
so mutations share unchanged subtrees and avoid full copies.

### Package Setup

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/apple/swift-collections", from: "1.1.4"),
],
targets: [
    .target(
        name: "AppFeature",
        dependencies: [
            .product(name: "Collections", package: "swift-collections"),
        ]
    ),
]
```

### Usage in State

```swift
import Collections

struct AppReducer: Reducer {
    struct State: Hashable {
        // Items keyed by their ID — O(log n) lookup and update
        var items: TreeDictionary<Item.ID, Item> = [:]
    }

    enum Action: Actionable {
        case loaded(items: [Item])
        case insert(Item)
        case delete(id: Item.ID)
        case update(Item)
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case let .loaded(items):
            // Build the dictionary from the loaded array
            state.items = TreeDictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        case let .insert(item):
            state.items[item.id] = item

        case let .delete(id):
            state.items[id] = nil

        case let .update(item):
            state.items[item.id] = item
        }
        return state
    }
}
```

### Accessing Items in a View

```swift
// Ordered list — convert to array sorted by a stable key
List(store.items.values.sorted(by: { $0.name < $1.name })) { item in
    ItemRowView(item: item)
}

// Direct lookup by ID — O(log n)
if let item = store.items[itemId] {
    ItemDetailView(item: item)
}
```

---

## 2. `@CowBox` — Copy-on-Write State

### Why

Every `reduce` call does `var state = oldState`.
For a large struct with many properties, this triggers a full value copy even if only one property changes.
The `@CowBox` macro wraps the struct's storage in a reference-counted box with copy-on-write semantics:
the copy is deferred until an actual mutation occurs, so unchanged state is shared for free.

### Package Setup

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/amine2233/Swift-CowBox", from: "2.0.0"),
],
targets: [
    .target(
        name: "AppFeature",
        dependencies: [
            .product(name: "CowBox", package: "swift-cowbox"),
        ]
    ),
]
```

### Usage

Apply `@CowBox` to the `State` struct. All stored properties become copy-on-write automatically.

```swift
import CowBox

struct AppReducer: Reducer {
    @CowBox
    struct State: Hashable {
        var items: TreeDictionary<Item.ID, Item> = [:]
        var isLoaded: LoadingState = .loaded
        var messageError: MessageError? = nil
        var sheet: Sheet? = nil
    }
}
```

`@CowBox` generates:

- A private `_Storage` class that holds all properties
- Getters/setters on `State` that trigger a copy only when the reference count is > 1
- `Equatable` / `Hashable` conformance forwarded to the storage

> No changes are needed in the reducer — `var state = oldState` continues to work as before. The copy is simply deferred until the first mutation.

---

## 3. Combining Both

Use `TreeDictionary` for the collection and `@CowBox` on the whole state for maximum efficiency.

```swift
import Collections
import CowBox

struct AppReducer: Reducer {
    @CowBox
    struct State: Hashable {
        var items: TreeDictionary<Item.ID, Item> = [:]
        var rowStates: TreeDictionary<Item.ID, ItemRowReducer.State> = [:]
        var isLoaded: LoadingState = .loaded
        var messageError: MessageError? = nil
        var sheet: Sheet? = nil
    }

    enum Action: Actionable {
        case load
        case loaded(items: [Item])
        case failure(failure: State.MessageError)
        case insert(Item)
        case delete(id: Item.ID)
        case update(Item)
        case row(id: Item.ID, action: ItemRowReducer.Action)
        case setSheet(State.Sheet?)
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState          // cheap — no copy until first mutation
        switch action {
        case .load:
            state.isLoaded = .loading // copy triggered here

        case let .loaded(items):
            state.items = TreeDictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            // Seed missing row states
            for item in items where state.rowStates[item.id] == nil {
                state.rowStates[item.id] = .init()
            }
            state.isLoaded = .loaded

        case let .failure(failure):
            state.messageError = failure
            state.isLoaded = .loaded

        case let .insert(item):
            state.items[item.id] = item
            state.rowStates[item.id] = .init()

        case let .delete(id):
            state.items[id] = nil
            state.rowStates[id] = nil

        case let .update(item):
            state.items[item.id] = item

        case let .row(id, rowAction):
            let current = state.rowStates[id] ?? .init()
            state.rowStates[id] = ItemRowReducer().reduce(oldState: current, with: rowAction)

        case let .setSheet(sheet):
            state.sheet = sheet
        }
        return state
    }
}
```
