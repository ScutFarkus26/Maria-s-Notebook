import Foundation

extension StudentLesson {
    /// Prefer the relationship's ID; fall back to snapshot for compatibility during transition.
    var resolvedLessonID: UUID {
        lesson?.id ?? lessonID
    }

    /// Prefer the relationship; fall back to snapshot for compatibility during transition.
    var resolvedStudentIDs: [UUID] {
        if !students.isEmpty { return students.map { $0.id } }
        // Convert string IDs back to UUIDs for CloudKit compatibility
        return studentIDs.compactMap { UUID(uuidString: $0) }
    }

    /// Order-insensitive key for quick equality/group checks.
    var studentGroupKey: String {
        if !studentGroupKeyPersisted.isEmpty { return studentGroupKeyPersisted }
        let ids = resolvedStudentIDs.sorted { $0.uuidString < $1.uuidString }
        return ids.map { $0.uuidString }.joined(separator: ",")
    }
}

