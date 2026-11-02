---
name: implementation-form
description: Guide to implementing a complete ReduxKit form, covering State, Action, Reducer, Middleware, Store, and SwiftUI integration with best practices for form state management, validation, and completion handling.
---

# Form Implementation

A form is a self-contained screen that collects input and reports its result to the presenter via a **completion callback**.
It owns its own store, defines its own `Completion` enum, and never touches the parent store directly.

## Rules

1. **The form owns its store** — created in `init`, never read from the environment.
2. **Result is reported via `onCompletion`** — a `(Completion) -> Void` closure passed at call site.
3. **`Completion` has exactly two cases**: `.done(result)` and `.cancel`.
4. **`State.isDisabled`** is a computed property on `State` that drives button disabled state — no extra action needed.
5. **Internal navigation** within the form uses `State.Sheet`.
6. **Child sub-sections** receive a derived store scoped to their own `State`/`Action`.
7. **Parent reducer delegates** child actions to the child reducer inline.
8. **Parent middleware delegates** child actions to the child middleware — child `.binding` actions
   flow through the parent store, so the parent middleware is the only place to process their side effects.

---

## 1. The Completion Enum

Every form declares a `Completion` enum inside the view. Two cases only — done with a result, or cancelled.

```swift
struct QRCodeEdit: View {
    enum Completion {
        case done(qrCode: QRCodeModel?)
        case cancel
    }

    var onCompletion: (Completion) -> Void
}
```

---

## 2. The Reducer

### State

The parent state must embed the child states so that `.derived(deriveState:deriveAction:)` can project into them via key path.

```swift
struct QRCodeEditReducer: Reducer {
    struct State: Hashable {
        var name: String = ""
        var content: String = ""
        var qrCode: QRCodeModel? = .make()

        // Child sub-states — required for derived store projection
        var eyeState: QRCodeEditEyeReducer.State = .init()
        var colorsState: QRCodeEditColorReducer.State = .init()

        // Computed validation — no action needed, derived from other fields
        var isDisabled: Bool {
            name.isEmpty || content.isEmpty
        }

        // Internal navigation for popovers within the form
        var sheet: Sheet?

        enum Sheet: Hashable, Identifiable {
            case eye
            case onPixel
            case offPixel
            case colors
            var id: Self { self }
        }
    }
}
```

Key points:

- `isDisabled` is a **computed property**, not stored state — it is derived automatically whenever `name` or `content` changes.
- `sheet` follows the same `State.Sheet` to scope the internal popovers within the form.

### Actions

```swift
extension QRCodeEditReducer {
    enum Action: Actionable {
        case setName(String)
        case setContent(String)
        case setSheet(State.Sheet?)
        case setQRCode(QRCodeModel?)
        case onPasteboard
        case setPasteboard(String?)
        // sub-section actions delegated to child reducers
        case setEyePattern(QRCodeEditEyeReducer.Action)
        case setColors(QRCodeEditColorReducer.Action)
    }
}
```

### Reducer

```swift
extension QRCodeEditReducer {
    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case let .setName(name):
            state.name = name
            state.qrCode = state.qrCode?.copy(name: name)
        case let .setContent(content):
            state.content = content
            state.qrCode = state.qrCode?.copy(content: content)
        case let .setSheet(Sheet):
            state.sheet = sheet
        case let .setQRCode(qrCode):
            state.qrCode = qrCode
        case let .setPasteboard(value):
            if let value {
                state.content = value
                state.qrCode = state.qrCode?.copy(content: value)
            }
        case .onPasteboard:
            break // handled by middleware
        case let .setColors(colorsAction):
            // Delegate to the child reducer — keeps child logic self-contained
            state.colorsState = QRCodeEditColorReducer().reduce(oldState: state.colorsState, with: colorsAction)
        case let .setEyePattern(eyeAction):
            state.eyeState = QRCodeEditEyeReducer().reduce(oldState: state.eyeState, with: eyeAction)
        }
        return state
    }
}
```

---

## 3. Middleware

The parent middleware handles its own side effects **and** delegates child actions to the
corresponding child middleware. This is required because child views use `store.binding` on
a derived store — every child action flows through the parent store as a wrapped parent action
(e.g. `.setColors(.setCornerRadius(…))`). The parent middleware must intercept it and forward
it to the child middleware so that child side effects are still processed.

```swift
final class QRCodeEditorMiddleware: Middleware, @unchecked Sendable {
    typealias Action = QRCodeEditReducer.Action
    typealias State = QRCodeEditReducer.State

    struct Dependencies {
        var getCopyString: () -> String?

        static var production: Dependencies {
            .init {
                UIPasteboard.general.string
            }
        }
    }

    let dependencies: Dependencies
    // Child middlewares owned by the parent — same lifetime as the form store
    let colorMiddleware: QRCodeEditColorMiddleware
    let eyeMiddleware: QRCodeEditEyeMiddleware

    init(
        dependencies: Dependencies = .production,
        colorMiddleware: QRCodeEditColorMiddleware = .init(),
        eyeMiddleware: QRCodeEditEyeMiddleware = .init()
    ) {
        self.dependencies = dependencies
        self.colorMiddleware = colorMiddleware
        self.eyeMiddleware = eyeMiddleware
    }

    func process(state: State, with action: Action) async -> Action? {
        switch action {
        case .onPasteboard:
            return .setPasteboard(dependencies.getCopyString())

        // Delegate child actions to their own middleware.
        // The child middleware receives the projected child state and child action,
        // and its response is re-wrapped into the parent action space.
        case let .setColors(colorsAction):
            guard let childAction = await colorMiddleware.process(
                state: state.colorsState,
                with: colorsAction
            ) else { return nil }
            return .setColors(childAction)

        case let .setEyePattern(eyeAction):
            guard let childAction = await eyeMiddleware.process(
                state: state.eyeState,
                with: eyeAction
            ) else { return nil }
            return .setEyePattern(childAction)

        default:
            return nil
        }
    }
}
```

In the form's `init`, pass `.production` (or a stub in tests):

```swift
self.store = Store(
    initialState: QRCodeEditReducer.State(),
    reducer: QRCodeEditReducer(),
    middlewares: [QRCodeEditorMiddleware(dependencies: .production)]
)
```

---

## 4. The Form View

The form creates its store in `init`. It never reads a store from the environment.

```swift
struct QRCodeEdit: View {
    enum Completion {
        case done(qrCode: QRCodeModel?)
        case cancel
    }

    var onCompletion: (Completion) -> Void

    @State private var store: Store<QRCodeEditReducer.State, QRCodeEditReducer.Action>
    @Environment(\.dismiss) private var dismiss

    init(onCompletion: @escaping (Completion) -> Void) {
        self.onCompletion = onCompletion
        self.store = Store(
            initialState: QRCodeEditReducer.State(),
            reducer: QRCodeEditReducer(),
            middlewares: [QRCodeEditorMiddleware()]
        )
    }

    var body: some View {
        NavigationStack {
            VStack {
                // Form fields using store bindings
                TextField("Name", text: store.binding(\.name, send: { .setName($0) }))
                TextField("Content", text: store.binding(\.content, send: { .setContent($0) }))

                // Pasteboard button — non-async side effect via dispatch
                Button("Paste") { store.dispatch(.onPasteboard) }

                // Preview bound to the live model
                QRCodePreviewView(
                    qrCode: store.binding(\.qrCode, send: { .setQRCode($0) })
                )
            }
            // Internal popover navigation
            .popover(item: store.binding(\.sheet, send: { .setSheet($0) })) { sheet in
                switch sheet {
                case .eye:
                    QRCodeEditEye(
                        store: store.derived(
                            deriveState: \.eyeState,
                            deriveAction: { .setEyePattern($0) }
                        )
                    )
                case .colors:
                    QRCodeEditColor(
                        store: store.derived(
                            deriveState: \.colorsState,
                            deriveAction: { .setColors($0) }
                        )
                    )
                // ... other cases
                }
            }
            .navigationTitle("Create QR Code")
            .toolbar {
                // Cancel — call completion then dismiss
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCompletion(.cancel)
                        dismiss()
                    }
                }
                // Done — call completion with result then dismiss
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onCompletion(.done(qrCode: store.qrCode))
                        dismiss()
                    }
                    .disabled(store.isDisabled)
                }
            }
        }
    }
}
```

Key points:

- `store.binding(\.field, send: { .setField($0) })` provides two-way binding for every form field.
- `store.dispatch(.onPasteboard)` is used for non-async actions that don't need `await`.
- Both toolbar actions call `onCompletion(…)` **before** `dismiss()`.
- `store.isDisabled` reads the computed property directly via `@dynamicMemberLookup` — no extra state needed.

---

## 5. Child Views with Derived Stores

Sub-sections of the form (e.g. color pickers, pattern selectors) receive a store scoped to their
own `State`/`Action` via `store.derived(deriveState:deriveAction:)`.

> **How `.binding` flows through the parent store**: when a child view calls
> `store.binding(\.cornerRadius, send: { .setCornerRadius($0) })` on its derived store,
> the action is wrapped via `deriveAction` before it reaches the parent store. The parent store
> receives `.setColors(.setCornerRadius(…))` — the parent reducer and parent middleware both
> see it and must handle it.

```swift
// Parent passes a scoped store
QRCodeEditColor(
    store: store.derived(
        deriveState: \.colorsState,
        deriveAction: { .setColors($0) }
    )
)
```

```swift
// Child view — receives the store, does not create it
struct QRCodeEditColor: View {
    @State private var store: Store<QRCodeEditColorReducer.State, QRCodeEditColorReducer.Action>
    @Environment(\.dismiss) private var dismiss

    init(store: Store<QRCodeEditColorReducer.State, QRCodeEditColorReducer.Action>) {
        self.store = store
    }

    var body: some View {
        ScrollView {
            // Slider bound to store state
            Slider(
                value: store.binding(\.cornerRadius, send: { .setCornerRadius($0) }),
                in: 0...16,
                step: 1.0
            )
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
```

```swift
// Child reducer — independent, no knowledge of parent state
struct QRCodeEditColorReducer: Reducer {
    enum Action: Actionable {
        case setBackgroundColor(Color)
        case setForegroundColor(Color)
        case setCornerRadius(CGFloat)
        case setQuietZonePixelCount(Float)
    }

    struct State: Hashable {
        var background: Color = .black
        var foreground: Color = .black
        var cornerRadius: CGFloat = 0
        var quietZonePixelCount: Float = 2
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case let .setBackgroundColor(color): state.background = color
        case let .setForegroundColor(color): state.foreground = color
        case let .setCornerRadius(radius):   state.cornerRadius = radius
        case let .setQuietZonePixelCount(v): state.quietZonePixelCount = v
        }
        return state
    }
}
```

---

## 6. Previews

```swift
#Preview {
    QRCodeEdit(onCompletion: { _ in })
}

#Preview("Color Editor") {
    NavigationStack {
        QRCodeEditColor(
            store: Store(
                initialState: QRCodeEditColorReducer.State(),
                reducer: QRCodeEditColorReducer(),
                middlewares: []
            )
        )
    }
}
```

Child view previews create their store inline — no parent needed.

---

## 7. Calling Site

```swift
// In the parent view's .sheet(item:)
case .qrCodeAdd:
    QRCodeEdit { completion in
        switch completion {
        case let .done(qrCode):
            if let qrCode { store.dispatch(.insert(qrCode)) }
        case .cancel:
            break
        }
    }
```

The parent store is only touched inside the `onCompletion` closure — the form itself is fully decoupled.
