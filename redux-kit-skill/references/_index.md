# References Index

## Setup

| File | What it covers |
|------|----------------|
| [installation.md](installation.md) | SPM / Xcode setup, available products, platform requirements |

## Architecture

| File | What it covers |
|------|----------------|
| [unidirectional-flow.md](unidirectional-flow.md) | The three rules: one app store, feature reducers lifted via `Prism`, store injected through SwiftUI `Environment` with `Provider` |
| [prism.md](prism.md) | `Prism<Source, Target>` — embed/extract type; foundation for `.lifted()`, `.keyed()`, and `.offset()` |
| [reducer-keyed.md](reducer-keyed.md) | `.keyed(keyPath:prism:)` — scope a reducer or middleware to one entry in a `[Key: State]` dictionary |
| [reducer-offset.md](reducer-offset.md) | `.offset(keyPath:prism:)` — scope a reducer or middleware to one element in a `[State]` array by index |
| [reducer-optional.md](reducer-optional.md) | `.optional()` — wrap a reducer or middleware to handle `Optional<State>`, no-op when state is `nil` |
| [reducer-filter-offset.md](reducer-filter-offset.md) | `.filterOffset(keyPath:prism:predicate:)` — apply an action to all array elements matching a predicate (batch operations) |
| [reducer-filtered-keyed.md](reducer-filtered-keyed.md) | `.filteredKeyed(keyPath:prism:predicate:)` — apply an action to all dictionary values matching a predicate (batch operations on keyed state) |
| [reducer-sorted-offset.md](reducer-sorted-offset.md) | `.sortedOffset(keyPath:prism:comparator:)` — apply a reducer to one array element by index, then re-sort the array with a comparator |
| [reducer-comparable-offset.md](reducer-comparable-offset.md) | `.comparableOffset(keyPath:prism:comparator:positionInjector:)` — like `.sortedOffset()` but also injects rank/position metadata into every element after sorting |
| [reducer-tree-keyed.md](reducer-tree-keyed.md) | `.treeKeyed()`, `.treeComparableKeyed()`, `.treeFilterKeyed()` — `ReduxKitExtensions` variants for `TreeDictionary<Key, State>` (key-sorted, O(log n)) |

## Feature Implementation

| File | What it covers |
|------|----------------|
| [implementation.md](implementation.md) | Full feature example — State, Action, Reducer, Middleware, Store, SwiftUI view |
| [undoable-store.md](undoable-store.md) | Undo/redo — `UndoableStore` (snapshots), `DescriptiveUndoableStore` (named history), `ActionableUndoableStore` (inverse actions through middleware) |
| [implementation-screen.md](implementation-screen.md) | List screen — `.load`/`.loaded`/`.failure`, delete with confirmation dialog, error alert with optional Retry, `@Environment` store, previews |
| [implementation-form.md](implementation-form.md) | Form screens — `Completion` callback, form-owned store in `init`, `State.isDisabled`, `State.Sheet` for internal popovers, child views with derived stores |
| [best-practice.md](best-practice.md) | App & module structure — App/Feature split, `AppReducer` composition, `AppMiddleware`, wiring new features, `Dependencies` stubs for previews and tests |
| [best-practice-list.md](best-practice-list.md) | List patterns — simple value row, ephemeral `@State` row, lifted `RowReducer` keyed by `Item.ID`, parent/child store connection, previews |
| [best-practice-app-state.md](best-practice-app-state.md) | State optimisations — `TreeDictionary` (swift-collections) for keyed storage, `@CowBox` for copy-on-write structs, combined usage |
| [implementation-tests.md](implementation-tests.md) | Reducer unit tests, Middleware tests with stub dependencies, Store integration tests including cancellation |
| [testing-store.md](testing-store.md) | `ReduxKitTesting` library — `TestStore` (`send`/`receive`/`finish`, exhaustivity), `ReducerProbe`/`expectReduce`, `MiddlewareProbe` |

## Navigation

| File | What it covers |
|------|----------------|
| [navigation.md](navigation.md) | Single `NavigationStack` app — singleton `NavigationStore.shared`, path binding, push / pop / root patterns |
| [navigation-tabbar.md](navigation-tabbar.md) | Tab bar app — per-tab path arrays, two-way `TabView` sync, semantic actions, per-tab `NavigationStack` binding |
| [navigation-sheet.md](navigation-sheet.md) | Modal sheets — `State.Sheet` nested enum inside the feature state, single `setSheet(Sheet?)` action, `.sheet(item:)` binding |
