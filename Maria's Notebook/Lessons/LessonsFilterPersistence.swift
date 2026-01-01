import Foundation

struct LessonsFilterPersistence {
    /// Store normalized subject keys in a stable order
    static func serializeExpandedSubjects(_ set: Set<String>) -> String {
        return set.sorted().joined(separator: "|")
    }

    static func deserializeExpandedSubjects(_ raw: String) -> Set<String> {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        return Set(raw.split(separator: "|").map { String($0) })
    }

    static func normalizeSubjectKey(_ subject: String) -> String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
