import Foundation

extension Array {
    /// Creates a dictionary from the array using a key extractor.
    /// - Parameter keyPath: A key path to extract the key from each element
    /// - Returns: A dictionary with keys from the key path and values as the elements
    func toDictionary<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Key: Element] {
        Dictionary(uniqueKeysWithValues: map { ($0[keyPath: keyPath], $0) })
    }
    
    /// Creates a dictionary from the array using a key extractor function.
    /// - Parameter key: A function that extracts a key from each element
    /// - Returns: A dictionary with keys from the function and values as the elements
    func toDictionary<Key: Hashable>(by key: (Element) -> Key) -> [Key: Element] {
        Dictionary(uniqueKeysWithValues: map { (key($0), $0) })
    }
    
    /// Groups elements by a key extractor.
    /// - Parameter key: A function that extracts a key from each element
    /// - Returns: A dictionary grouping elements by their keys
    func grouped<Key: Hashable>(by key: (Element) -> Key) -> [Key: [Element]] {
        Dictionary(grouping: self, by: key)
    }
}

