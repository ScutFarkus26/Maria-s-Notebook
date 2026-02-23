import Foundation

extension Sequence where Element: Identifiable {
    /// Creates a dictionary mapping each element's ID to the element itself
    /// - Returns: Dictionary with IDs as keys and elements as values
    /// - Note: If duplicate IDs exist, the first element is kept
    func dictionaryByID() -> [Element.ID: Element] {
        Dictionary(map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

extension Collection {
    /// More readable alternative to !isEmpty
    var isNotEmpty: Bool { !isEmpty }
}
