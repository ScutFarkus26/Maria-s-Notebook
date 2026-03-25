import Foundation

extension Dictionary where Key == UUID {
    /// Looks up a value by a UUID string, returning nil if the string is not a valid UUID.
    /// Replaces the common pattern: `if let uuid = UUID(uuidString: key), let v = dict[uuid] { ... }`
    subscript(uuidString key: String) -> Value? {
        guard let uuid = UUID(uuidString: key) else { return nil }
        return self[uuid]
    }
}

extension Array {
    /// Creates a dictionary from the array using a key extractor.
    /// - Parameter keyPath: A key path to extract the key from each element
    /// - Returns: A dictionary with keys from the key path and values as the elements
    /// - Note: If duplicate keys exist, the first element is kept.
    func toDictionary<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Key: Element] {
        Dictionary(map { ($0[keyPath: keyPath], $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Creates a dictionary from the array using a key extractor function.
    /// - Parameter key: A function that extracts a key from each element
    /// - Returns: A dictionary with keys from the function and values as the elements
    /// - Note: If duplicate keys exist, the first element is kept.
    func toDictionary<Key: Hashable>(by key: (Element) -> Key) -> [Key: Element] {
        Dictionary(map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
    }
    
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
