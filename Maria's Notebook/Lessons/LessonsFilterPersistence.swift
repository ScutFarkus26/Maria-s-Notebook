import Foundation

struct LessonsFilterPersistence {
    /// Store normalized area keys in a stable order
    static func serializeExpandedAreas(_ set: Set<String>) -> String {
        return set.sorted().joined(separator: "|")
    }

    static func deserializeExpandedAreas(_ raw: String) -> Set<String> {
        if raw.trimmed().isEmpty { return [] }
        return Set(raw.split(separator: "|").map { String($0) })
    }

    static func normalizeAreaKey(_ area: String) -> String {
        area.normalizedForComparison()
    }
}
