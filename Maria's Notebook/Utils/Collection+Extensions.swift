import Foundation

extension Sequence where Element: Identifiable {
}

extension Collection {
    /// More readable alternative to !isEmpty
    var isNotEmpty: Bool { !isEmpty }
}

extension Array {
    /// Splits the array into elements matching and not matching the predicate, preserving order within each sequence.
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
