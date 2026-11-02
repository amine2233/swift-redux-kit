import Collections

extension TreeDictionary {
    public init(_ values: Value...) where Key == Value.ID, Value: Identifiable {
        self.init(values)
    }
}

extension TreeDictionary {
    public init<S>(_ values: S) where Key == Value.ID, Value: Identifiable, S: Sequence, S.Element == Value {
        self.init(
            uniqueKeysWithValues: values.map { element in
                (element.id, element)
            }
        )
    }
}
