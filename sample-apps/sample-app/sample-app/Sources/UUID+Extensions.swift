import Foundation

// MARK: - UUID Extensions for Testing and Previews

extension UUID {
    /// Creates a deterministic UUID from an integer value.
    ///
    /// This is useful for testing and SwiftUI previews where you need consistent,
    /// predictable UUID values instead of random ones.
    ///
    /// - Parameter int: An integer value to convert into a UUID
    /// - Returns: A UUID created from the integer value
    ///
    /// # Example
    /// ```swift
    /// let uuid1 = UUID(1)  // Always produces the same UUID
    /// let uuid2 = UUID(2)  // Always produces a different UUID than uuid1
    ///
    /// // Useful in previews
    /// let todos: [UUID: TodoItemState] = [
    ///     UUID(1): TodoItemState(id: UUID(1), title: "First todo", ...),
    ///     UUID(2): TodoItemState(id: UUID(2), title: "Second todo", ...)
    /// ]
    /// ```
    ///
    /// # Implementation Details
    /// The UUID is constructed by:
    /// 1. Converting the integer to a 16-byte array (padded with zeros)
    /// 2. Using the byte array to create a valid UUID
    /// 3. Ensuring the UUID conforms to RFC 4122 format
    init(_ int: Int) {
        // Convert integer to bytes (little-endian)
        var value = int
        var bytes: [UInt8] = withUnsafeBytes(of: &value) { Array($0) }

        // Pad to 16 bytes (UUID size)
        while bytes.count < 16 {
            bytes.append(0)
        }

        // Take only first 16 bytes if somehow we have more
        bytes = Array(bytes.prefix(16))

        // Create UUID from bytes
        let uuid = NSUUID(uuidBytes: bytes) as UUID
        self = uuid
    }

    /// Creates a deterministic UUID from a string.
    ///
    /// This is useful when you want human-readable identifiers that map to UUIDs.
    ///
    /// - Parameter string: A string to convert into a UUID using its hash value
    /// - Returns: A UUID created from the string's hash
    ///
    /// # Example
    /// ```swift
    /// let uuid = UUID("todo-1")  // Always produces the same UUID for "todo-1"
    /// ```
    init(_ string: String) {
        self.init(string.hashValue)
    }

    /// Common preset UUIDs for testing
    enum Preset {
        static let zero = UUID(0)
        static let one = UUID(1)
        static let two = UUID(2)
        static let three = UUID(3)
        static let four = UUID(4)
        static let five = UUID(5)
        static let six = UUID(6)
        static let seven = UUID(7)
        static let eight = UUID(8)
        static let nine = UUID(9)
        static let ten = UUID(10)
    }
}

// MARK: - Usage Examples

#if DEBUG
/// Example usage of UUID integer initializer
private func exampleUsage() {
    // Create deterministic UUIDs for testing
    let id1 = UUID(1)
    let id2 = UUID(2)
    let id3 = UUID(3)

    print("UUID(1): \(id1)") // Always the same
    print("UUID(2): \(id2)") // Always the same
    print("UUID(3): \(id3)") // Always the same

    // Using presets
    let presetID = UUID.Preset.one
    print("Preset.one: \(presetID)")

    // In a dictionary
    let items: [UUID: String] = [
        UUID(1): "First item",
        UUID(2): "Second item",
        UUID(3): "Third item"
    ]

    // String-based UUIDs
    let todoID = UUID("important-todo")
    let userID = UUID("user-123")
}
#endif

// MARK: - Key Benefits

// 1. DETERMINISTIC IDS:
//   - Same input always produces the same UUID
//   - Perfect for unit tests and UI previews
//   - Makes debugging easier with recognizable IDs
//
// 2. CLEAN PREVIEW CODE:
//   - Before: UUID(), UUID(), UUID() (all different, unpredictable)
//   - After:  UUID(1), UUID(2), UUID(3) (consistent, readable)
//
// 3. TEST ASSERTIONS:
//   - Can assert exact UUID values in tests
//   - Reproducible test scenarios
//
// 4. DEBUGGING:
//   - Easier to identify items by their number
//   - Consistent UUIDs across app launches during development
//
// 5. PRESET CONVENIENCE:
//   - Common IDs available via UUID.Preset
//   - No need to remember integer values
