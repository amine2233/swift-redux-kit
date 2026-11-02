---
name: navigation-sheet
description: Implement sheet presentation in a SwiftUI app using a dedicated `State.Sheet` enum, a single `setSheet(Sheet?)` action, and the `.sheet(item:)` modifier to drive presentation and dismissal.
---

# Navigation — Sheets

## Rules

1. **`State.Sheet` belongs to the presenting feature** — it is a nested enum inside the feature's `State`, never in `NavigationStore` or `AppState`.
2. **The `.sheet(item:)` modifier belongs to the screen that owns the state** — not a child view.
3. **One action handles both present and dismiss** — `setSheet(State.Sheet?)` covers the full lifecycle. `nil` dismisses, a value presents.
4. **Sheet cases carry all the data the presented screen needs** — pass IDs or values as associated values, not the full model.

---

## 1. State

Add a `sheet: Sheet?` property and a nested `Sheet` enum to the feature state. `Sheet` must conform to both `Identifiable` and `Hashable`.

```swift
struct AppReducer: Reducer {
    struct State: Hashable {
        var sheet: Sheet?

        enum Sheet: Identifiable, Hashable {
            var id: Self { self }

            case qrCodeAdd
            case qrCodeEdit(identifier: QRCodeModel.ID)
        }
    }
}
```

`var id: Self { self }` is the standard `Identifiable` implementation when the enum is already `Hashable`.

---

## 2. Action

One action covers the full present / dismiss lifecycle.

```swift
extension AppReducer {
    enum Action: Actionable {
        case setSheet(State.Sheet?)
        // ... other feature actions
    }
}
```

---

## 3. Reducer

```swift
extension AppReducer {
    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case let .setSheet(sheet):
            state.sheet = sheet
        // ... other cases
        }
        return state
    }
}
```

---

## 4. View

Apply `.sheet(item:)` on the screen that owns the store.
Pass `store.binding(\.sheet, send: { .setSheet($0) })` as the item binding — SwiftUI automatically dispatches `.setSheet(nil)` when the user swipes to dismiss.

```swift
struct AppView: View {
    @Environment(\.store) private var store

    var body: some View {
        ExampleView()
            .sheet(item: store.binding(\.sheet, send: { .setSheet($0) })) { sheet in
                switch sheet {
                case .qrCodeAdd:
                    QRCodeEditView { completion in
                        switch completion {
                        case let .done(qrCode):
                            if let qrCode { store.dispatch(.insert(qrCode)) }
                        case .cancel:
                            break
                        }
                    }
                case let .qrCodeEdit(identifier):
                    QRCodeUpdateView(identifier) { completion in
                        switch completion {
                        case let .done(qrCode):
                            if let qrCode { store.dispatch(.insert(qrCode)) }
                        case .cancel:
                            break
                        }
                    }
                }
            }
    }
}
```

---

## 5. Presenting and Dismissing

### Present

```swift
// Present add sheet
store.dispatch(.setSheet(.qrCodeAdd))

// Present edit sheet with an ID
store.dispatch(.setSheet(.qrCodeEdit(identifier: item.id)))
```

### Dismiss

```swift
// Programmatic dismiss
store.dispatch(.setSheet(nil))
```

SwiftUI dismisses automatically (and dispatches `.setSheet(nil)`) when the user swipes down the sheet — no extra handling needed.

---

## 6. Adding a New Sheet

1. Add a case to `State.Sheet`.
2. Add a branch to the `.sheet(item:)` switch in the view.

The action and reducer require no changes — `setSheet` already handles any `Sheet?` value.
