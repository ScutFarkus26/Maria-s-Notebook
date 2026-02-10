import Foundation

extension Collection where Element: Identifiable, Element.ID == UUID {
    /// Returns an array of UUID strings for all elements in the collection
    nonisolated var uuidStrings: [String] {
        map { $0.id.uuidString }
    }
}

extension Sequence where Element: Identifiable, Element.ID == UUID {
    /// Returns an array of UUID strings for all elements in the sequence
    nonisolated var uuidStrings: [String] {
        map { $0.id.uuidString }
    }
}

extension UUID {
    /// Convenient accessor for uuidString
    var stringValue: String { uuidString }
}
