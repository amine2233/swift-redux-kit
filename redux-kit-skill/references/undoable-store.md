---
name: undoable-store
description: Guide to adding undo/redo functionality to a Redux store using UndoableStore, DescriptiveUndoableStore, or ActionableUndoableStore.
---

# UndoableStore

ReduxKit provides three store wrappers that add undo/redo to any `Store`. All three conform to `UndoableStoreable` and are available from the `ReduxKitExtensions` module.

| Variant | State snapshot | Action metadata | Middleware on undo/redo |
|---------|---------------|-----------------|------------------------|
| `UndoableStore` | Yes | No | No — state bypasses reducer |
| `DescriptiveUndoableStore` | Yes | `undoDescription` label | No — state bypasses reducer |
| `ActionableUndoableStore` | No | Inverse action | Yes — dispatches through middleware |

**Choose the simplest one that meets your needs.** Most features only need `UndoableStore`.

## Rules

1. **State must be `Sendable & Hashable`** — the store uses equality to detect actual changes and takes snapshots.
2. **Use `@State private var store = UndoableStore(…)`** — same ownership model as `Store`.
3. **Set a `historyLimit`** — `0` means unlimited; always set a reasonable cap (10–100) to avoid unbounded memory growth.
4. **Group rapid updates with `beginGrouping()`** — sliders, drag gestures and text typing should share a single history entry.
5. **Only `ActionableUndoableStore` runs middleware on undo/redo** — use it when reversing an action requires side effects (e.g. API calls).

---

## 1. `UndoableStore` — Snapshot-based Undo/Redo

The simplest option. Wraps a `Store` and saves full state snapshots before each action.
Restores state directly via `Store.setState`, bypassing the reducer and middleware.

### State & Action requirements

```swift
// State must be Sendable & Hashable
struct CanvasState: Sendable, Hashable {
    var strokes: [DrawingStroke] = []
    var currentColor: Color = .black
    var currentSize: Double = 3.0
}

// Actions conform to Actionable as usual
enum CanvasAction: Actionable {
    case addStroke(DrawingStroke)
    case clear
    case setColor(Color)
    case setSize(Double)
}
```

### Initialization

```swift
// Option 1 — create directly (preferred)
@State private var store = UndoableStore(
    initialState: CanvasState(),
    reducer: CanvasReducer(),
    historyLimit: 50
)

// Option 2 — wrap an existing store
let inner = Store(initialState: CanvasState(), reducer: CanvasReducer(), middlewares: [])
let store = UndoableStore(store: inner, historyLimit: 50)
```

### SwiftUI view

```swift
@MainActor
struct CanvasView: View {
    @State private var store = UndoableStore(
        initialState: CanvasState(),
        reducer: CanvasReducer(),
        historyLimit: 50
    )

    var body: some View {
        VStack {
            // Undo / Redo toolbar
            HStack {
                Button {
                    store.undoDispatch()          // fire-and-forget
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!store.canUndo)

                Button {
                    store.redoDispatch()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!store.canRedo)

                Text("Undo: \(store.undoCount)  Redo: \(store.redoCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // State access via @dynamicMemberLookup
            Text("Strokes: \(store.strokes.count)")

            Button("Clear") {
                store.dispatch(.clear)
            }
        }
        .task(id: someInput) {
            await store.send(.addStroke(newStroke))   // awaitable in async contexts
        }
    }
}
```

---

## 2. `DescriptiveUndoableStore` — Named Undo/Redo

Extends `UndoableStore` with human-readable action labels for use in undo/redo menus.
Actions must conform to `DescriptiveActionable`.

### Protocol requirement

```swift
enum DocumentAction: DescriptiveActionable {
    case setText(String)
    case appendText(String)
    case toggleBold
    case setFontSize(Int)
    case clear

    var undoDescription: String {
        switch self {
        case .setText:              "Typing"
        case let .appendText(text): "Insert '\(text.prefix(20))'"
        case .toggleBold:           "Bold Formatting"
        case let .setFontSize(n):   "Change Font Size to \(n)"
        case .clear:                "Clear Document"
        }
    }
}
```

### Initialization

```swift
@State private var store = DescriptiveUndoableStore(
    initialState: DocumentState(),
    reducer: DocumentReducer(),
    historyLimit: 100
)
```

### Undo/Redo menu in SwiftUI

```swift
Menu {
    ForEach(
        Array(store.undoDescriptions.prefix(10).enumerated()),
        id: \.offset
    ) { index, description in
        Button("Undo \(description)") {
            Task { await store.undo(steps: index + 1) }
        }
    }
} label: {
    Label(
        store.nextUndoDescription.map { "Undo \($0)" } ?? "Undo",
        systemImage: "arrow.uturn.backward.circle"
    )
}
.disabled(!store.canUndo)
```

### Additional APIs (over `UndoableStore`)

```swift
store.nextUndoDescription   // String? — label of the action that will be undone
store.nextRedoDescription   // String? — label of the action that will be redone
store.undoDescriptions      // [String] — all undo labels, most recent first
store.redoDescriptions      // [String] — all redo labels
store.undoHistory           // [HistoryEntry<State, Action>]
store.redoHistory           // [HistoryEntry<State, Action>]

await store.undo(steps: 3)     // undo 3 steps at once
await store.redo(steps: 2)     // redo 2 steps at once
await store.undoToIndex(5)     // undo back to the 6th history entry
```

---

## 3. `ActionableUndoableStore` — Middleware-aware Undo/Redo

Dispatches the **inverse action** through the normal store flow when undoing/redoing.
Use this when undo must trigger side effects (e.g. API requests to reverse a server-side change).

### Protocol requirements

```swift
// State must conform to UndoableState (Sendable & Hashable)
struct TaskState: UndoableState {
    var tasks: [TaskExample] = []
}

// Actions must conform to InvertibleActionable
enum TaskAction: InvertibleActionable {
    typealias State = TaskState

    case createTask(id: String, title: String)
    case deleteTask(id: String, title: String)

    func inverse(state: TaskState) -> Self? {
        switch self {
        case let .createTask(id, title): .deleteTask(id: id, title: title)
        case let .deleteTask(id, title): .createTask(id: id, title: title)
        }
    }

    var undoDescription: String {
        switch self {
        case .createTask: "Create Task"
        case .deleteTask: "Delete Task"
        }
    }
}
```

> Return `nil` from `inverse(state:)` for actions that cannot be undone. Those actions are still dispatched but are not recorded in history.

### Initialization

```swift
@State private var store = ActionableUndoableStore(
    initialState: TaskState(),
    reducer: TaskReducer(),
    middlewares: [TaskMiddleware()],
    historyLimit: 50
)
```

### Lifecycle middleware (optional)

```swift
// Receive willUndo / didUndo / willRedo / didRedo events
actor UndoRedoLogger: Middleware {
    typealias State = TaskState
    typealias Action = UndoRedoLifecycleAction<TaskAction>

    func process(state: TaskState, with action: Action) async -> Action? {
        switch action {
        case let .willUndo(a): print("About to undo: \(a.undoDescription)")
        case let .didUndo(a):  print("Did undo: \(a.undoDescription)")
        default: break
        }
        return nil
    }
}

@State private var store = ActionableUndoableStore(
    initialState: TaskState(),
    reducer: TaskReducer(),
    middlewares: [TaskMiddleware()],
    historyLimit: 50,
    lifecycleMiddlewares: [UndoRedoLogger()]
)
```

---

## Shared API — All Three Variants

### Properties

```swift
store.canUndo     // Bool — whether undo is available
store.canRedo     // Bool — whether redo is available
store.undoCount   // Int  — number of states/actions in undo history
store.redoCount   // Int  — number of states/actions in redo history
```

### Methods

```swift
// Async (await in Task or .task modifier)
await store.send(.someAction)
await store.undo()
await store.redo()

// Fire-and-forget (use in Button actions)
store.dispatch(.someAction)
store.undoDispatch()
store.redoDispatch()

// Grouping — next action shares the current history entry
store.beginGrouping()
await store.send(.setSize(5))   // not recorded as a new undo point

// Clear all history
store.clearHistory()
```

### State access

```swift
// Direct property access via @dynamicMemberLookup
store.someProperty   // equivalent to store.state.someProperty

// SwiftUI Binding
store.binding(\.text, send: { .setText($0) })
store.binding(extract: { $0.count }, embed: { .setCount($0) })
```

---

## Grouping Rapid Updates

Use `beginGrouping()` before any action that is part of a continuous gesture or live typing, so that only the final committed state appears as a single undo point.

```swift
// Slider — group every intermediate value, keep only the last
Slider(
    value: Binding(
        get: { store.brushSize },
        set: { size in
            store.beginGrouping()          // merge into the previous entry
            Task { await store.send(.setSize(size)) }
        }
    ),
    in: 1...20
)
```

---

## Memory Considerations

- Each history entry stores a **full state snapshot** (for `UndoableStore` / `DescriptiveUndoableStore`).
- Keep state structs small and use value types to minimise snapshot cost.
- Always set `historyLimit` — 50 is a reasonable default for most document-like features.
- Call `store.clearHistory()` when starting a new document or session to release old snapshots immediately.
