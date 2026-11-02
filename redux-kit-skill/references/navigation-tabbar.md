---
name: navigation-tabbar
description: Implement tab bar navigation in a SwiftUI app using a dedicated NavigationStore and NavigationReducer to manage navigation state and actions for multiple tabs.
---

# Navigation — Tab Bar

## Rules

1. **One `NavigationStore` per app** — navigation state (active tab + per-tab paths) is never embedded in `AppState`. It lives in its own dedicated store.
2. **Singleton** — `NavigationStore.shared` is accessed directly from any view. There is no need to pass it through the environment.
3. **One path array per tab** — each tab has its own `[TabPath]` array that drives its `NavigationStack`.
4. **Semantic actions** — prefer `.home(.profile)` over `.setHomePaths([.profile])`. Semantic actions atomically switch the tab *and* set the path in one dispatch.
5. **Two-way tab sync** — SwiftUI's `TabView(selection:)` owns a local `@State var mainTab`. It must be kept in sync with `navigationStore.mainTab` in both directions.

---

## 1. Define the NavigationStore

```swift
// NavigationStore.swift
import Foundation
import ReduxKit

typealias NavigationStore = Store<NavigationReducer.State, NavigationReducer.Action>
typealias NavigationState = NavigationReducer.State

extension NavigationStore {
    @MainActor
    static let shared = NavigationStore(
        initialState: NavigationReducer.State(),
        reducer: NavigationReducer(),
        middlewares: []
    )
}
```

---

## 2. Define the NavigationReducer

### State and path types

```swift
// NavigationReducer.swift
import ReduxKit

struct NavigationReducer: Reducer {
    struct State: Hashable {
        var mainTab: MainTab = .home
        var homePaths: [HomePath] = []
        var equipmentPaths: [EquipmentPath] = []
        var logbookPaths: [LogbookPath] = []
    }
}

extension NavigationReducer.State {
    enum MainTab: Hashable {
        case home
        case equipment
        case logbook
        case search
    }

    enum HomePath: Hashable {
        case profile
    }

    enum EquipmentPath: Hashable {
        // add cases as the tab grows
    }

    enum LogbookPath: Hashable {
        case logDetail(id: UUID)
    }
}
```

### Action

Two kinds of actions coexist:

- **Low-level** (`setMainTab`, `setHomePaths`, …) — replace a single piece of navigation state directly.
- **Semantic** (`.home(_)`, `.logbook(_)`, …) — switch to the right tab *and* set the right path atomically.

```swift
extension NavigationReducer {
    enum Action: Actionable {
        // low-level
        case setMainTab(State.MainTab)
        case setHomePaths([State.HomePath])
        case setEquipmentPaths([State.EquipmentPath])
        case setLogbookPaths([State.LogbookPath])
        // semantic
        case home(Home)
        case equipment(Equipment)
        case logbook(Logbook)
    }
}

extension NavigationReducer.Action {
    enum Home {
        case root
        case profile
    }

    enum Equipment {
        case root
    }

    enum Logbook {
        case root
        case logDetail(id: UUID)
    }
}
```

### Reducer

```swift
extension NavigationReducer {
    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case let .setMainTab(tab):
            state.mainTab = tab
        case let .setHomePaths(paths):
            state.homePaths = paths
        case let .setEquipmentPaths(paths):
            state.equipmentPaths = paths
        case let .setLogbookPaths(paths):
            state.logbookPaths = paths
        case let .home(destination):
            state.mainTab = .home
            switch destination {
            case .root:    state.homePaths = []
            case .profile: state.homePaths = [.profile]
            }
        case let .equipment(destination):
            state.mainTab = .equipment
            switch destination {
            case .root: state.equipmentPaths = []
            }
        case let .logbook(destination):
            state.mainTab = .logbook
            switch destination {
            case .root:               state.logbookPaths = []
            case let .logDetail(id):  state.logbookPaths = [.logDetail(id: id)]
            }
        }
        return state
    }
}
```

---

## 3. Entry Point — MainView

`MainView` orchestrates the splash/app switch and owns the two-way tab sync.

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
    // Local SwiftUI tab selection — kept in sync with navigationStore.mainTab
    @State private var mainTab: NavigationState.MainTab = .home

    public init() {}

    public var body: some View {
        switch store.isLoaded {
        case true:
            MainTabView(mainTab: $mainTab)
                // User tapped a tab → sync into NavigationStore
                .onChange(of: mainTab, onMainTabChange)
                // NavigationStore changed tab (programmatic) → sync into local state
                .onChange(of: navigationStore.mainTab, onNavigationStoreMainTabChange)
        case false:
            SplashView()
                .task { await store.send(.load) }
        }
    }

    private func onMainTabChange() {
        // Delay by one frame to avoid the "NavigationAuthority bound path tried to update
        // multiple times per frame" warning when switching tabs rapidly.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: NSEC_PER_SEC / 60)
            navigationStore.dispatch(.setMainTab(mainTab))
        }
    }

    private func onNavigationStoreMainTabChange() {
        guard mainTab != navigationStore.mainTab else { return }
        mainTab = navigationStore.mainTab
    }
}
```

> The one-frame delay in `onMainTabChange` is intentional — it prevents SwiftUI's "Update NavigationAuthority bound path tried to update multiple times per frame" warning when the tab changes.

---

## 4. MainTabView

```swift
// MainTabView.swift
import SwiftUI

struct MainTabView: View {
    @Binding var mainTab: NavigationState.MainTab

    var body: some View {
        TabView(selection: $mainTab) {
            Tab("Home", systemImage: "house", value: NavigationState.MainTab.home) {
                HomeView()
            }
            #if DEBUG
            Tab("Equipment", systemImage: "door.sliding.right.hand.closed", value: NavigationState.MainTab.equipment) {
                EquipmentView()
            }
            #endif
            Tab("Logbook", systemImage: "book.pages", value: NavigationState.MainTab.logbook) {
                LogbookListView()
            }
            Tab("Search", systemImage: "magnifyingglass", value: NavigationState.MainTab.search, role: .search) {
                SearchView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
```

---

## 5. Per-Tab NavigationStack

Each tab root view owns its `NavigationStack` and binds its path to the navigation store.

```swift
// HomeView.swift
@MainActor
struct HomeView: View {
    @State private var navigationStore = NavigationStore.shared

    var body: some View {
        NavigationStack(path: navigationStore.binding(
            \.homePaths,
            send: NavigationReducer.Action.setHomePaths
        )) {
            HomeRootView()
                .navigationDestination(for: NavigationState.HomePath.self) { path in
                    switch path {
                    case .profile: ProfileView()
                    }
                }
        }
    }
}
```

```swift
// LogbookListView.swift
@MainActor
struct LogbookListView: View {
    @State private var navigationStore = NavigationStore.shared

    var body: some View {
        NavigationStack(path: navigationStore.binding(
            \.logbookPaths,
            send: NavigationReducer.Action.setLogbookPaths
        )) {
            LogbookRootView()
                .navigationDestination(for: NavigationState.LogbookPath.self) { path in
                    switch path {
                    case let .logDetail(id): LogDetailView(id: id)
                    }
                }
        }
    }
}
```

---

## 6. Navigating from Any View

Because `NavigationStore.shared` is a singleton, any view can navigate without being passed the store.

### Switch tab and navigate (semantic — preferred)

```swift
// Go to logbook and open a log detail
NavigationStore.shared.dispatch(.logbook(.logDetail(id: log.id)))

// Go to home root
NavigationStore.shared.dispatch(.home(.root))

// Go to home profile
NavigationStore.shared.dispatch(.home(.profile))
```

### Low-level path manipulation

```swift
// Push onto current tab's stack
let current = NavigationStore.shared.homePaths
NavigationStore.shared.dispatch(.setHomePaths(current + [.profile]))

// Pop to root of current tab
NavigationStore.shared.dispatch(.setHomePaths([]))

// Switch tab only
NavigationStore.shared.dispatch(.setMainTab(.logbook))
```

Use `dispatch(_:)` (from `ReduxKitExtensions`) in synchronous contexts — it fires the action in a detached `Task`. Use `await store.send(…)` when you need to wait for the reducer to complete.

---

## 7. Adding a New Destination

1. Add a case to the relevant `XxxPath` enum (e.g. `HomePath`).
2. Add a case to the corresponding semantic `Action.Home` enum (optional but recommended).
3. Handle the new case in the reducer's semantic action branch.
4. Add a `navigationDestination` branch in the tab's root view.

No other files need to change.
