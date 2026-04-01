import Foundation

extension Sequence where Element: Identifiable {
    /// Creates a dictionary mapping each element's ID to the element itself
    /// - Returns: Dictionary with IDs as keys and elements as values
    /// - CDNote: If duplicate IDs exist, the first element is kept
    func dictionaryByID() -> [Element.ID: Element] {
        Dictionary(map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

extension Collection {
    /// More readable alternative to !isEmpty
    var isNotEmpty: Bool { !isEmpty }
}

extension Array {
    /// Splits the array into elements matching and not matching the predicate, preserving order within each group.
    func partitioned(by predicate: (Element) -> Bool) -> (matching: [Element], rest: [Element]) {
        var matching: [Element] = []
        var rest: [Element] = []
        for element in self {
            if predicate(element) {
                matching.append(element)
            } else {
                rest.append(element)
            }
        }
        return (matching, rest)
    }
}
