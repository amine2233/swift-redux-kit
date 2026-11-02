# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReduxKit is a Swift package implementing Redux-like unidirectional data flow architecture using Swift's Observation framework.
This is a clone of [swift-unidirectional-flow-0.2.6](https://github.com/mecid/swift-unidirectional-flow/tree/0.2.6)
adapted to use Combine instead of the newer Observable framework.

**Platform Requirements:**

- macOS 14+
- iOS 17+
- Swift 6.0+

## Package Structure

The package consists of three main modules:

1. **ReduxKit** (Core): Contains the fundamental Redux architecture components
   - `Store<State, Action>`: Main store implementation using `@Observable` and `@MainActor`
   - `Reducer<State, Action>`: Protocol defining state mutations
   - `Middleware<State, Action>`: Protocol for side effects and action interception
   - `Actionable`: Protocol that all actions must conform to
   - `Prism<Source, Target>`: Utility for embedding/extracting values between types

2. **ReduxKitExtensions**: Convenience extensions for Store and Middleware
   - `Store.send(thunk:)`: Async thunk support
   - `Store.dispatch(_:)`: Non-blocking action dispatch
   - `LoggerMiddleware`: Debug middleware for logging actions and state

3. **ReduxKitUI**: SwiftUI integration utilities
   - `Provider`: SwiftUI component for injecting store into environment

4. **ExampleApp**: Example GitHub repository search app demonstrating usage

## Key Architecture Concepts

### State Flow

The architecture follows a strict unidirectional data flow:

1. Actions are dispatched to the Store via `send(_:)` or `dispatch(_:)`
2. Reducer processes action synchronously and produces new state
3. State change triggers observation updates
4. Middleware processes action asynchronously (can dispatch new actions)

**IMPORTANT**: In `Store.swift:39-45`, the reducer runs synchronously BEFORE middleware. This means:

- State is updated immediately when action is sent
- Middleware sees the post-reduction state
- Middleware can dispatch additional actions via recursive `send()` calls

### Composition Patterns

**Reducers** can be composed using:

- `CombinedReducer`: Combines multiple reducers
- `.lifted(keyPath:prism:)`: Scopes reducer to nested state
- `.optional()`: Handles optional state
- `.keyed(keyPath:prism:)`: Operates on dictionary state
- `.offset(keyPath:prism:)`: Operates on array state

**Middleware** supports similar composition:

- `.lifted(keyPath:prism:)`: Scopes middleware to nested state
- `.optional()`: Handles optional state
- `.keyed(keyPath:prism:)`: Operates on dictionary state
- `.offset(keyPath:prism:)`: Operates on array state

### Thread Safety

- Store is marked `@MainActor` - all state access must be on main thread
- State and Action types must conform to `Sendable`
- Middleware process methods are `async` and can run on any actor

## Development Commands

### Setup

```bash
# Install mise tools (including mint and swiftlint)
make mise_install

# Activate mise environment
make mise_activate

# Bootstrap mint packages (required for most commands)
make mint_bootstrap
```

### Building

```bash
# Build the package
make build
# Or directly:
swift build

# Build on Linux (via Docker)
make build_linux
```

### Testing

```bash
# Run tests with coverage
make test

# Run tests directly (no coverage)
swift test

# Run specific test
swift test --filter <TestName>
```

### Code Quality

```bash
# Format code using executor
make format

# Check formatting (fails if changes needed)
make check_format

# Check documentation with swiftlint
make check_documentation
```

### Documentation

```bash
# Build DocC documentation
make build_documentation

# Serve documentation locally (on port 8000)
make start_documentation_server
```

## Important Implementation Details

### Store Binding Behavior

When using `Store.binding(_:send:)` in SwiftUI (Store.swift:147-170):

- The reducer runs synchronously within the SwiftUI transaction
- Middleware runs asynchronously in a Task AFTER the transaction
- This ensures UI updates happen immediately while side effects run later

### Middleware Return Values

- Returning an `Action?` from middleware will recursively call `send()` with that action
- Returning `nil` stops the middleware chain for that action
- Middleware processes sequentially in the order provided to Store init

### Deprecated API

`Store.derived(deriveState:deriveAction:)` is deprecated - use multiple independent stores instead of derived stores.

## Test Files Location

- Core tests: `Tests/ReduxKitTests/`
- Test files cover: Store, Reducer, Middleware, and Prism functionality
