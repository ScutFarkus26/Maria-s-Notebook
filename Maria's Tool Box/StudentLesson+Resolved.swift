import Foundation

extension StudentLesson {
    /// Prefer the relationship's ID; fall back to snapshot for compatibility during transition.
    var resolvedLessonID: UUID {
        lesson?.id ?? lessonID
    }

    /// Prefer the relationship; fall back to snapshot for compatibility during transition.
    var resolvedStudentIDs: [UUID] {
        if !students.isEmpty { return students.map { $0.id } }
        return studentIDs
    }

    /// Order-insensitive key for quick equality/group checks.
    var studentGroupKey: String {
        let persisted = (self as? StudentLesson)?.studentGroupKeyPersisted ?? ""
        if !persisted.isEmpty { return persisted }
        let ids = resolvedStudentIDs.sorted { $0.uuidString < $1.uuidString }
        return ids.map { $0.uuidString }.joined(separator: ",")
    }
}
