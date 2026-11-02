/// Type that defines a way to embed and extract a value from another type.
public struct Prism<Source, Target>: Sendable {
    package let embed: @Sendable (Target) -> Source
    package let extract: @Sendable (Source) -> Target?

    public init(
        embed: @Sendable @escaping (Target) -> Source,
        extract: @Sendable @escaping (Source) -> Target?
    ) {
        self.embed = embed
        self.extract = extract
    }
}
