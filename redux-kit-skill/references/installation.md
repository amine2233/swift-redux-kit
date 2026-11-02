---
name: installation
description: Guide to installing the ReduxKit package in a Swift project using Swift Package Manager or Xcode's built-in package management.
---

# Installation

## Requirements

| Requirement | Minimum version |
|-------------|----------------|
| Swift | 6.0+ |
| iOS | 17+ |
| macOS | 14+ |

## Swift Package Manager

Add `redux-kit` as a dependency in your `Package.swift`:

```swift
// Package.swift
dependencies: [
    .package(url: "https://gitlab.com/intech-consulting-app/swift-packages/redux-kit.git", from: "2.0.0")
]
```

you can also add the dependency through `swift package add` command:

```bash
swift package add-dependency https://gitlab.com/intech-consulting-app/swift-packages/redux-kit.git --from 2.0.0
```

Then add the products you need to your target's dependencies:

```swift
.target(
    name: "MyFeature",
    dependencies: [
        .product(name: "ReduxKit", package: "redux-kit"),
        .product(name: "ReduxKitExtensions", package: "redux-kit"),
        .product(name: "ReduxKitUI", package: "redux-kit"),
    ]
)
```

you can also add the products through `swift package edit` command:

```bash
swift package add-target-dependency ReduxKit MyFeature --package redux-kit
```

## Available Products

| Product | Description |
|---------|-------------|
| `ReduxKit` | Core store, reducer, middleware, and action primitives |
| `ReduxKitExtensions` | Thunk support, non-blocking dispatch, and `LoggerMiddleware` |
| `ReduxKitUI` | SwiftUI `Provider` component for environment injection |

## Xcode Project

1. Open your project in Xcode.
2. Go to **File → Add Package Dependencies…**
3. Enter the repository URL: `git@gitlab.com:intech-consulting-app/swift-packages/redux-kit.git`
4. Select the version rule (e.g. **Up to Next Major** from `2.0.0`).
5. Add the products you need to your target.
