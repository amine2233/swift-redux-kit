// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var targets: [Target] = [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
        name: "ReduxKit"
    ),
    .testTarget(
        name: "ReduxKitTests",
        dependencies: ["ReduxKit"]
    ),
    .target(
        name: "ReduxKitUI",
        dependencies: [
            .target(name: "ReduxKit")
        ]
    ),
    .target(
        name: "ReduxKitExtensions",
        dependencies: [
            .target(name: "ReduxKit"),
            .product(name: "Collections", package: "swift-collections")
        ]
    ),
    .testTarget(
        name: "ReduxKitExtensionsTests",
        dependencies: ["ReduxKitExtensions"]
    ),
    .target(
        name: "ReduxKitTesting",
        dependencies: [
            .target(name: "ReduxKit")
        ]
    ),
    .testTarget(
        name: "ReduxKitTestingTests",
        dependencies: ["ReduxKitTesting"]
    )
]

#if os(macOS)
targets += [
    .executableTarget(
        name: "ExampleApp",
        dependencies: [
            .target(name: "ReduxKit")
        ]
    )
]
#endif

let package = Package(
    name: "redux-kit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other
        // packages.
        .library(
            name: "ReduxKit",
            targets: ["ReduxKit"]
        ),
        .library(
            name: "ReduxKitExtensions",
            targets: ["ReduxKitExtensions"]
        ),
        .library(
            name: "ReduxKitUI",
            targets: ["ReduxKitUI"]
        ),
        .library(
            name: "ReduxKitTesting",
            targets: ["ReduxKitTesting"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.4")
    ],
    targets: targets
)
