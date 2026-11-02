---
name: redux-kit
description: ReduxKit SwiftUI framework — Provide an opinioned Redux implementation. Use when writing SwiftUI application in a project that depends on the ReduxKit package.
---

# Redux Kit

This skill provides full knowledge of designing the **ReduxKit** SwiftUI framework for building application and micro features, cross-platform UI and logic.

## Core Principle

ReduxKit is built on the core principle of **unidirectional data flow** and **state management**. It provides a structured way to manage application state, handle side effects, and build reusable UI components that are consistent across platforms.

## Quick Reference

### Components

| Component | Usage |
|-----------|-------|
| Installation | Add via SPM or Xcode — see [installation.md](references/installation.md) |
| Implementation | State, Action, Reducer, Middleware, Store, and SwiftUI view — see [implementation.md](references/implementation.md) |
| Test Implementation | Reducer, Middleware, and Store integration tests — see [implementation-tests.md](references/implementation-tests.md) |
| Testing with ReduxKitTesting | `TestStore`, `ReducerProbe`, `MiddlewareProbe` sugar — exhaustive state/effect assertions — see [testing-store.md](references/testing-store.md) |
| Unidirectional Flow | App architecture rules: one store, lifted feature reducers, Environment injection — see [unidirectional-flow.md](references/unidirectional-flow.md) |
| Prism | `Prism<Source, Target>` embed/extract type, defining prisms on parent actions, using with `.lifted()` — see [prism.md](references/prism.md) |
| Reducer `.keyed()` | Scope reducer/middleware to a `[Key: State]` dictionary entry — see [reducer-keyed.md](references/reducer-keyed.md) |
| Reducer `.offset()` | Scope reducer/middleware to a `[State]` array element by index — see [reducer-offset.md](references/reducer-offset.md) |
| Reducer `.optional()` | Wrap reducer/middleware for `Optional<State>`, no-op when nil — see [reducer-optional.md](references/reducer-optional.md) |
| Reducer `.filterOffset()` | Apply an action to all array elements matching a predicate — batch bulk operations — see [reducer-filter-offset.md](references/reducer-filter-offset.md) |
| Reducer `.filteredKeyed()` | Apply an action to all dictionary values matching a predicate — batch bulk operations on keyed state — see [reducer-filtered-keyed.md](references/reducer-filtered-keyed.md) |
| Reducer `.sortedOffset()` | Apply a reducer to one array element by index, then re-sort the array with a comparator — see [reducer-sorted-offset.md](references/reducer-sorted-offset.md) |
| Reducer `.comparableOffset()` | Like `.sortedOffset()` but also injects rank/position metadata into every element — leaderboards, ranked lists — see [reducer-comparable-offset.md](references/reducer-comparable-offset.md) |
| Reducer `treeKeyed` / `treeComparableKeyed` / `treeFilterKeyed` | `ReduxKitExtensions` variants for `TreeDictionary<Key, State>` — key-sorted O(log n) storage — see [reducer-tree-keyed.md](references/reducer-tree-keyed.md) |
| Navigation | Singleton `NavigationStore`, `NavigationStack` binding, push/pop patterns — see [navigation.md](references/navigation.md) |
| Navigation (Tab Bar) | Singleton `NavigationStore` with per-tab paths, two-way tab sync, semantic actions — see [navigation-tabbar.md](references/navigation-tabbar.md) |
| Navigation (Sheet) | `State.Sheet` nested enum, single `setSheet` action, `.sheet(item:)` binding — see [navigation-sheet.md](references/navigation-sheet.md) |
| Form Implementation | Completion callback pattern, form-owned store, `State.isDisabled`, `State.Destination`, child derived stores — see [implementation-form.md](references/implementation-form.md) |
| App Structure & Best Practices | App/Feature module split, `AppReducer` composition, `AppMiddleware`, wiring new features, `Dependencies` stubs — see [implementation-best-practice.md](references/implementation-best-practice.md) |
| List with Lifted Row | Simple value row, ephemeral `@State` row, `RowReducer` keyed by `Item.ID`, parent/child store wiring — see [best-practice-list.md](references/best-practice-list.md) |
| App State Optimisations | `TreeDictionary` for keyed collections, `@CowBox` for copy-on-write state, combined usage — see [best-practice-app-state.md](references/best-practice-app-state.md) |
| Screen Implementation | `.load`/`.loaded`, delete confirmation, failure alert with retry, `@Environment` store — see [implementation-screen.md](references/implementation-screen.md) |
| Implementation dependencies | Best practices for using `Dependencies` in middleware, avoiding `@Dependency` in reducers, stubbing in tests — see [implementation-dependencies.md](references/implementation-dependencies.md) |
| Services | `StoreService` for external sources that push (timer, socket, reachability, database) — register with `services:`, start with `run()` — see [services.md](references/services.md) |
| undoable stores | Guide to adding undo/redo functionality to a Redux store [undoable-store.md](undoable-store.md) |

## Detailed References

- [Installation](references/installation.md): Swift Package Manager and Xcode setup, available products, platform requirements.
- [Implementation](references/implementation.md): Full feature example (State, Action, Reducer, Middleware, Store, SwiftUI view).
- [Test Implementation](references/implementation-tests.md): Reducer unit tests, Middleware tests with stub dependencies, and Store integration tests including cancellation.
- [Testing with ReduxKitTesting](references/testing-store.md): The `ReduxKitTesting` library — `TestStore` for exhaustive integration tests (`send`/`receive`/`finish`), `ReducerProbe` and `expectReduce` for reducers, `MiddlewareProbe` for middleware.
- [Unidirectional Flow](references/unidirectional-flow.md): The three rules — one app store, feature reducers lifted via `Prism`, store injected through SwiftUI `Environment` using `Provider`.
- [Prism](references/prism.md): `Prism<Source, Target>` type — how to define prisms on parent action enums and use them with `.lifted()`, `.keyed()`, and `.offset()`.
- [Reducer `.keyed()`](references/reducer-keyed.md): Scope a reducer or middleware to a single `[Key: State]` dictionary entry — prism definition, seeding entries, dispatching from views.
- [Reducer `.offset()`](references/reducer-offset.md): Scope a reducer or middleware to a single `[State]` array element by integer index — prism definition, initialisation, dispatching.
- [Reducer `.optional()`](references/reducer-optional.md): Wrap a reducer or middleware to operate on `Optional<State>` — combined with `.lifted()` for nullable sub-states, standalone usage.
- [Reducer `.filterOffset()`](references/reducer-filter-offset.md): Apply an action to all `[State]` array elements satisfying a predicate — static prisms, dynamic prism factories, combining multiple filters, batch dispatch from views.
- [Reducer `.filteredKeyed()`](references/reducer-filtered-keyed.md): Apply an action to all `[Key: State]` dictionary values satisfying a predicate — static prisms, combining with `.keyed()` in CombinedReducer, batch dispatch from views.
- [Reducer `.sortedOffset()`](references/reducer-sorted-offset.md): Apply a reducer to one `[State]` array element by index, then re-sort the array with a comparator — prism definition, combining with CombinedReducer, index fragility warning.
- [Reducer `.comparableOffset()`](references/reducer-comparable-offset.md): Like `.sortedOffset()` but injects rank/position metadata into every element via `positionInjector` — leaderboards, priority rankings, multi-criteria comparators.
- [Reducer `TreeDictionary` variants](references/reducer-tree-keyed.md): `.treeKeyed()`, `.treeComparableKeyed()`, `.treeFilterKeyed()` from `ReduxKitExtensions` —
  single-entry and predicate-batch reducers for `TreeDictionary<Key, State>` (key-sorted, O(log n)).
- [Navigation](references/navigation.md): Singleton `NavigationStore.shared`, `NavigationStack` path binding, push/pop/root navigation patterns, adding new destinations.
- [Navigation (Tab Bar)](references/navigation-tabbar.md): Singleton `NavigationStore.shared` with per-tab path arrays, two-way `TabView` sync, semantic actions, per-tab `NavigationStack` binding.
- [Navigation (Sheet)](references/navigation-sheet.md): `State.Sheet` nested enum inside the feature state, single `setSheet(Sheet?)` action, `.sheet(item:)` binding, present/dismiss patterns.
- [Form Implementation](references/implementation-form.md): Completion callback pattern, form-owned store in `init`, `State.isDisabled` computed property, `State.Destination` for internal popovers, child views with derived stores, previews.
- [App Structure & Best Practices](references/best-practice.md): App/Feature module split, project layout, `AppReducer` composition via `Prism`, `AppMiddleware`, wiring a new feature end-to-end.
- [List with Lifted Row](references/best-practice-list.md): Three row patterns — simple value row, ephemeral `@State` row, and `RowReducer` lifted into the parent store keyed by `Item.ID` with full parent/child state wiring and previews.
- [App State Optimisations](references/best-practice-app-state.md): `TreeDictionary` (swift-collections) for O(log n) keyed storage, `@CowBox` macro for copy-on-write state structs, SPM setup for both packages, and combined usage example.
- [Screen Implementation](references/implementation-screen.md): Full screen pattern — `.load`/`.loaded`/`.failure`, delete with `.confirmDelete` dialog, error alert with optional Retry, `@Environment` store, `.setEnvironmentStore()` previews.
- [Implementation dependencies](references/implementation-dependencies.md): Best practices for using `Dependencies` in middleware, avoiding `@Dependency` in reducers, stubbing dependencies in tests, and example usage in a feature middleware.
- [Services](references/services.md): `StoreService` — the inbound counterpart of `Middleware`. Wrapping an external source in an `AsyncStream`,
  `ClosureService`, registering with `services:`, starting with `run()` from `.task` or any async context, gating on state, and asserting emitted actions.
- [undoable-store.md](undoable-store.md): Guide to adding undo/redo functionality to a Redux store using UndoableStore, DescriptiveUndoableStore, or ActionableUndoableStore.
