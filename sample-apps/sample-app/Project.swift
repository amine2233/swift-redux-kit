import ProjectDescription

let project = Project(
    name: "sample-app",
    packages: [
        .local(path: "../../../redux-kit")
    ],
    targets: [
        .target(
            name: "sample-app",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.sample-app",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": ""
                    ]
                ]
            ),
            buildableFolders: [
                "sample-app/Sources",
                "sample-app/Resources"
            ],
            dependencies: [
                .package(product: "ReduxKit", type: .runtime),
                .package(product: "ReduxKitExtensions", type: .runtime),
                .package(product: "ReduxKitUI", type: .runtime)
            ]
        ),
        .target(
            name: "sample-appTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.sample-appTests",
            infoPlist: .default,
            buildableFolders: [
                "sample-app/Tests"
            ],
            dependencies: [
                .target(name: "sample-app"),
                .package(product: "ReduxKitTesting", type: .runtime)
            ]
        )
    ]
)
