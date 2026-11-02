---
name: best-practice
description: Best practices for structuring a ReduxKit app, including project layout, app vs feature modules, navigation patterns, and state management techniques.
---

# Application Structure & Best Practices

This document describes how to structure a full ReduxKit application and its feature modules.

## Rules

1. **One App module, many Feature modules** — the app target is thin: it only wires feature reducers together,
   owns `NavigationStore`, and provides the store to the SwiftUI environment.
2. **Feature modules are self-contained** — each feature has its own `Reducer`, `Middleware`, `View`, and `Dependencies`.
   It knows nothing about other features.
3. **Never use `@Dependency`** — always use a `Dependencies` struct with a `static var production`. This keeps middleware testable.
4. **Feature reducers are lifted, not rewritten** — use `.lifted(keyPath:prism:)` to embed a feature reducer/middleware into the app-level types.
5. **`NavigationStore` is a singleton** — one instance per app, owned by the App module, accessed as `NavigationStore.shared`.

---

## 1. Project Layout

```
MyApp (App Target)
├── App/
│   ├── MyApp.swift               ← @main entry point, creates the AppStore
│   ├── AppReducer.swift          ← CombinedReducer lifting all feature reducers
│   ├── AppStore.swift            ← typealias + EnvironmentValues key
│   ├── AppView.swift             ← Root view, reads store from @Environment
│   ├── SplashView.swift          ← Launch screen shown while app initialises
│   └── Navigation/
│       ├── NavigationStore.swift ← Singleton NavigationStore
│       └── NavigationReducer.swift
│
MyFeature (Swift Package / local package)
├── FeatureReducer.swift
├── FeatureMiddleware.swift
├── FeatureView.swift
└── FeatureStore.swift            ← typealias only
```

---

## 2. App Module

### SplashView

Shown during launch while the app store initialises. Keep it static — no logic.

```swift
struct SplashView: View {
    var body: some View {
        Image(.appIcon128)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 128, height: 128)
    }
}
```

### AppReducer

Composes all feature reducers via `CombinedReducer` + `.lifted(keyPath:prism:)`.

```swift
// AppReducer.swift
struct AppReducer: Reducer {
    struct State: Hashable {
        var isLoaded: Bool = false
        var feature: FeatureReducer.State = .init()
        // add one property per feature
    }

    enum Action: Actionable {
        case load
        case setIsLoaded(Bool)
        case feature(FeatureReducer.Action)
        // add one case per feature
    }

    // Prism for each feature action
    static var featurePrism: Prism<Action, FeatureReducer.Action> {
        .init(embed: Action.feature) {
            guard case let .feature(action) = $0 else { return nil }
            return action
        }
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .load:
            break // handled by middleware
        case let .setIsLoaded(value):
            state.isLoaded = value
        case .feature:
            break // handled by lifted reducer below
        }
        // Lift feature reducers
        state = FeatureReducer()
            .lifted(keyPath: \.feature, prism: AppReducer.featurePrism)
            .reduce(oldState: state, with: action)
        return state
    }
}
```

### AppStore — typealias + Environment key

```swift
// AppStore.swift
import ReduxKit
import ReduxKitUI
import SwiftUI

typealias AppStore = Store<AppReducer.State, AppReducer.Action>

extension EnvironmentValues {
    @Entry var store: AppStore = AppStore(
        initialState: .init(),
        reducer: AppReducer(),
        middlewares: []
    )
}
```

### App Entry Point

```swift
// MyApp.swift
import ReduxKitUI
import SwiftUI

@main
struct MyApp: App {
    private let store = AppStore(
        initialState: .init(),
        reducer: AppReducer(),
        middlewares: [
            AppMiddleware(dependencies: .production),
            FeatureMiddleware(dependencies: .production)
                .lifted(keyPath: \.feature, prism: AppReducer.featurePrism),
        ]
    )

    var body: some Scene {
        WindowGroup {
            Provider(\.store, store) {
                AppView()
            }
        }
    }
}
```

### AppView

The root view. Reads the store from `@Environment` and switches between `SplashView` and `MainView` based on `isLoaded`.

```swift
// AppView.swift
@MainActor
struct AppView: View {
    @Environment(\.store) private var store
    @State private var navigationStore = NavigationStore.shared

    var body: some View {
        if store.isLoaded {
            MainView()
        } else {
            SplashView()
                .task { await store.send(.load) }
        }
    }
}
```

### AppMiddleware

Handles app-level lifecycle: loading initial data, registering services.

```swift
// AppMiddleware.swift
final class AppMiddleware: Middleware, @unchecked Sendable {
    typealias Action = AppReducer.Action
    typealias State = AppReducer.State

    struct Dependencies {
        var load: () async throws -> Void

        static var production: Dependencies {
            .init(load: {
                // register services, warm caches, etc.
            })
        }
    }

    let dependencies: Dependencies
    init(dependencies: Dependencies = .production) {
        self.dependencies = dependencies
    }

    func process(state: State, with action: Action) async -> Action? {
        switch action {
        case .load:
            try? await dependencies.load()
            return .setIsLoaded(true)
        default:
            return nil
        }
    }
}
```

---

## 3. Feature Module

Each feature is an isolated Swift module (or folder). It defines its own types and has **no import of the App module**.

```swift
// FeatureReducer.swift
struct FeatureReducer: Reducer {
    struct State: Hashable {
        var items: [Item] = []
        var isLoaded: LoadingState = .loaded
    }

    enum Action: Actionable {
        case load
        case loaded(items: [Item])
        case failure(failure: State.MessageError)
    }

    func reduce(oldState: State, with action: Action) -> State {
        var state = oldState
        switch action {
        case .load:
            state.isLoaded = .loading
        case let .loaded(items):
            state.items = items
            state.isLoaded = .loaded
        case let .failure(failure):
            state.messageError = failure
            state.isLoaded = .loaded
        }
        return state
    }
}
```

```swift
// FeatureMiddleware.swift
final class FeatureMiddleware: Middleware, @unchecked Sendable {
    typealias Action = FeatureReducer.Action
    typealias State = FeatureReducer.State

    struct Dependencies {
        var fetchItems: () async throws -> [Item]

        static var production: Dependencies {
            .init(fetchItems: { try await ItemRepository.shared.fetchAll() })
        }
    }

    let dependencies: Dependencies
    init(dependencies: Dependencies = .production) {
        self.dependencies = dependencies
    }

    func process(state: State, with action: Action) async -> Action? {
        switch action {
        case .load: return await loadItems()
        default: return nil
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
}
```

```swift
// FeatureStore.swift
typealias FeatureStore = Store<FeatureReducer.State, FeatureReducer.Action>
```

---

## 4. Wiring a New Feature

When adding a new feature to the app:

1. Add a property to `AppReducer.State`:

   ```swift
   var myFeature: MyFeatureReducer.State = .init()
   ```

2. Add a case to `AppReducer.Action`:

   ```swift
   case myFeature(MyFeatureReducer.Action)
   ```

3. Add a `Prism` to `AppReducer`:

   ```swift
   static var myFeaturePrism: Prism<Action, MyFeatureReducer.Action> {
       .init(embed: Action.myFeature) {
           guard case let .myFeature(a) = $0 else { return nil }
           return a
       }
   }
   ```

4. Lift the reducer inside `AppReducer.reduce(oldState:with:)`:

   ```swift
   state = MyFeatureReducer()
       .lifted(keyPath: \.myFeature, prism: AppReducer.myFeaturePrism)
       .reduce(oldState: state, with: action)
   ```

5. Lift the middleware inside the `AppStore` initialiser in `MyApp.swift`:

   ```swift
   MyFeatureMiddleware(dependencies: .production)
       .lifted(keyPath: \.myFeature, prism: AppReducer.myFeaturePrism),
   ```

---

## 5. Dependencies Pattern

Every middleware wraps its external calls in a `Dependencies` struct.
This is the **only** pattern — never use `@Dependency` or global singletons directly.

```swift
struct Dependencies {
    var fetchItems: () async throws -> [Item]
    var saveItem: (Item) async throws -> Void

    // Production — hits the real database / API
    static var production: Dependencies {
        .init(
            fetchItems: { try await ItemRepository.shared.fetchAll() },
            saveItem: { try await ItemRepository.shared.save($0) }
        )
    }

    // Preview — returns static data instantly, no network
    static var preview: Dependencies {
        .init(
            fetchItems: { [.preview, .preview] },
            saveItem: { _ in }
        )
    }

    // Loading — hangs forever, for skeleton previews
    static var loading: Dependencies {
        .init(
            fetchItems: { try await Task.sleep(for: .seconds(9999)); return [] },
            saveItem: { _ in }
        )
    }

    // Failing — always throws, for error-state previews and tests
    static var failing: Dependencies {
        .init(
            fetchItems: { throw URLError(.notConnectedToInternet) },
            saveItem: { _ in throw URLError(.notConnectedToInternet) }
        )
    }
}
```

### SwiftUI Previews

```swift
#Preview("Loaded") {
    FeatureView()
        .setEnvironmentStore(
            FeatureStore(
                initialState: .init(items: [.preview, .preview]),
                reducer: FeatureReducer(),
                middlewares: [FeatureMiddleware(dependencies: .preview)]
            )
        )
}

#Preview("Loading") {
    FeatureView()
        .setEnvironmentStore(
            FeatureStore(
                initialState: .init(isLoaded: .loading),
                reducer: FeatureReducer(),
                middlewares: [FeatureMiddleware(dependencies: .loading)]
            )
        )
}

#Preview("Error") {
    FeatureView()
        .setEnvironmentStore(
            FeatureStore(
                initialState: .init(
                    messageError: .init(
                        title: "Failed to load",
                        message: "No internet connection.",
                        canRetry: true
                    )
                ),
                reducer: FeatureReducer(),
                middlewares: []
            )
        )
}
```

### Unit Tests

```swift
@MainActor
struct FeatureMiddlewareTests {
    func makeMiddleware(throwing: Bool = false) -> FeatureMiddleware {
        FeatureMiddleware(dependencies: .init(
            fetchItems: {
                if throwing { throw URLError(.notConnectedToInternet) }
                return [.preview]
            }
        ))
    }

    @Test
    func loadReturnsItems() async {
        let middleware = makeMiddleware()
        let action = await middleware.process(state: .init(), with: .load)
        #expect(action == .loaded(items: [.preview]))
    }

    @Test
    func loadFailureReturnsFailureAction() async {
        let middleware = makeMiddleware(throwing: true)
        let action = await middleware.process(state: .init(), with: .load)
        if case .failure = action { } else { Issue.record("Expected .failure") }
    }
}
```
