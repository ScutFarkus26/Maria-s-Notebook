import Foundation

nonisolated extension Dictionary where Key == UUID {
    /// Looks up a value by a UUID string, returning nil if the string is not a valid UUID.
    /// Replaces the common pattern: `if let uuid = UUID(uuidString: key), let v = dict[uuid] { ... }`
    subscript(uuidString key: String) -> Value? {
        guard let uuid = UUID(uuidString: key) else { return nil }
        return self[uuid]
    }
}

nonisolated extension Array {
    /// Groups elements by a key extractor.
    /// - Parameter key: A function that extracts a key from each element
    /// - Returns: A dictionary grouping elements by their keys
    func grouped<Key: Hashable>(by key: (Element) -> Key) -> [Key: [Element]] {
        Dictionary(grouping: self, by: key)
    }
    
    /// Removes duplicates while preserving order.
    /// Elements are compared using their hash value.
    /// - Returns: An array with duplicates removed, preserving the original order
    func removingDuplicates() -> [Element] where Element: Hashable {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
    
    /// Removes duplicates based on a key extractor while preserving order.
    /// - Parameter key: A function that extracts a key from each element
    /// - Returns: An array with duplicates removed (keeping first occurrence), preserving order
    func removingDuplicates<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
