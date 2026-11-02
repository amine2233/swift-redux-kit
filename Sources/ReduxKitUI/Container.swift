import ReduxKit
#if canImport(SwiftUI)
import SwiftUI

/// A SwiftUI component that injects a store into the environment of its child views.
@MainActor
public struct Provider<Store, Content: View> {
    private let keyPath: WritableKeyPath<EnvironmentValues, Store>
    private let store: Store
    private let content: Content

    /// Constructs a `Provider`.
    ///
    /// - Parameter keyPath: A key path that indicates the property of the `EnvironmentValues` structure to
    /// update.
    /// - Parameter store: The store to set in this component’s environment.
    /// - Parameter content: A closure that constructs a component.
    ///
    /// - Note: `Provider` does not explicitly require its store to be an instance of `ImmutableData.Store`.
    public init(
        _ keyPath: WritableKeyPath<EnvironmentValues, Store>,
        _ store: Store,
        @ViewBuilder content: () -> Content
    ) {
        self.keyPath = keyPath
        self.store = store
        self.content = content()
    }
}

extension Provider: View {
    public var body: some View {
        content.environment(keyPath, store)
    }
}
#endif
