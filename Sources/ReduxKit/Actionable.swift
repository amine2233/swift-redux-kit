import Foundation

/// The actionable protocol need to attached into each action
public protocol Actionable: Sendable, Hashable {}

/// A wrapper struct that can hold any `Actionable` type.
///
/// This is useful when you need to pass around an `Actionable` instance as a single entity, without knowing
/// its specific type at compile time.
public struct AnyAction<Element: Actionable & Sendable>: Actionable, Sendable {
    /// The underlying `Actionable` instance that this `AnyAction` holds.
    public let action: Element

    /// Initializes a new `AnyAction` with the specified `action`.
    ///
    /// - Parameter action: The `Actionable` instance to hold.
    public init(action: Element) {
        self.action = action
    }
}

extension Actionable {
    /// Returns a new `AnyAction` that wraps this `Actionable` instance.
    ///
    /// This is useful when you need to pass around an `Actionable` instance as a single entity, without
    /// knowing its specific type at compile time.
    ///
    /// - Returns: A new `AnyAction` that holds this `Actionable` instance.
    public func eraseToAnyAction() -> AnyAction<Self> {
        .init(action: self)
    }
}
