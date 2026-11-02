---
name: navigation
description: Implement navigation in a SwiftUI app using a dedicated NavigationStore and NavigationReducer to manage navigation state and actions.
---

# Navigation

## Rules

1. **One `NavigationStore` per app** — navigation state is never embedded in `AppState`. It lives in its own dedicated store.
2. **Singleton** — `NavigationStore.shared` is accessed directly from any view. There is no need to pass it through the environment.
3. **No tab bar** — this pattern manages a single `NavigationStack`. Tab bar apps require an other approch see [navigation-tabbed.md](references/navigation-tabbed.md).

---

## 1. Define the NavigationStore

```swift
// NavigationStore.swift
import Foundation
import ReduxKit

typealias NavigationStore = Store<NavigationReducer.State, NavigationReducer.Action>

extension NavigationStore {
    @MainActor
    static let shared = Store(
        initialState: NavigationReducer.State(),
        reducer: NavigationReducer(),
        middlewares: []
    )
}
```

The `shared` instance is the single source of truth for navigation. It is created once and never recreated.

---

## 2. Define the NavigationReducer

```swift
// NavigationReducer.swift
import ReduxKit

struct NavigationReducer: Reducer {
    enum Action: Actionable {
        case setHomePaths([State.HomePath])
    }

    struct State: Hashable {
        var homePaths: [HomePath] = []
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case let .setHomePaths(homePaths):
            state.homePaths = homePaths
        }
        return state
    }
}
```

### Navigation path types

```swift
extension NavigationReducer.State {
    // Full destination set — used in NavigationStack path binding
    enum HomePath: Hashable {
        case detail(id: UUID)
    }
}
```

`HomePath` drives the `NavigationStack` path. Only screens that can be pushed onto the stack need a case here. The root screen is never in the path.

---

## 3. Wire into the Root View

The root view holds the `NavigationStack` and binds its `path` to `navigationStore.homePaths`.

```swift
// AppView.swift
import SwiftUI

@MainActor
struct AppView: View {
    @State private var navigationStore = NavigationStore.shared

    var body: some View {
        NavigationStack(path: navigationStore.binding(
            \.homePaths,
            send: NavigationReducer.Action.setHomePaths
        )) {
            HomeView()
                .navigationDestination(for: NavigationReducer.State.HomePath.self) { path in
                    switch path {
                    case let .detail(id):
                        DetailView(id: id)
                    }
                }
        }
    }
}
```

---

## 4. Entry Point

`MainView` is the app root. It handles the loading state and renders `AppView` when the app is ready.

```swift
// MainView.swift
import SwiftUI

@MainActor
public struct MainView: View {
    @State private var navigationStore = NavigationStore.shared
    @State private var store = Store(
        initialState: MainReducer.State(),
        reducer: MainReducer(),
        middlewares: [MainMiddleware()]
    )
    // or @Environment(\.store) private var store // if you prefer to inject the store through the environment instead of using a singleton

    public init() {}

    public var body: some View {
        VStack {
            switch store.isLoaded {
            case true:
                AppView()
            case false:
                SplashView()
            }
        }
        .task { await store.send(.load) }
    }
}
```

---

## 5. Navigating from Any View

Because `NavigationStore.shared` is a singleton, any view can dispatch navigation actions directly — no store needs to be passed down.

### Push to a detail screen

```swift
await NavigationStore.shared.send(.setHomePaths([.detail(id: item.id)]))
```

### Push onto the existing stack

```swift
let current = NavigationStore.shared.homePaths
await NavigationStore.shared.send(.setHomePaths(current + [.detail(id: item.id)]))
```

### Pop to root

```swift
await NavigationStore.shared.send(.setHomePaths([]))
```

### Pop one level

```swift
var paths = NavigationStore.shared.homePaths
paths.removeLast()
await NavigationStore.shared.send(.setHomePaths(paths))
```

### Non-blocking dispatch (from a synchronous context)

```swift
NavigationStore.shared.dispatch(.setHomePaths([.detail(id: item.id)]))
```

`dispatch(_:)` is from `ReduxKitExtensions` and fires the action in a detached `Task` without requiring `await`.

---

## 6. Adding a New Destination

1. Add a case to `NavigationReducer.State.HomePath`.
2. Add a `navigationDestination` branch in `AppView`.
3. Dispatch `.setHomePaths([.newScreen(…)])` from wherever the navigation is triggered.

No other files need to change.
