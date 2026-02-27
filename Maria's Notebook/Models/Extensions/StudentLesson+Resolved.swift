import Foundation

// MARK: - DenormalizedSchedulable Conformance

extension StudentLesson: DenormalizedSchedulable {
    /// Prefer the relationship; fall back to stored IDs for compatibility during transition.
    var resolvedStudentIDs: [UUID] {
        if !students.isEmpty { return students.map { $0.id } }
        return studentIDs.compactMap { UUID(uuidString: $0) }
    }

    // Bridge properties for protocol default implementations
    var lessonRelationshipID: UUID? { lesson?.id }
    var studentRelationshipIDStrings: [String] { students.map { $0.id.uuidString } }
}
