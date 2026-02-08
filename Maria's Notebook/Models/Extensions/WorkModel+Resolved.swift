import Foundation

extension WorkModel {
    /// Participants are the single source of truth for student membership.
    var resolvedStudentIDs: [UUID] {
        // CloudKit compatibility: Convert String IDs to UUIDs
        (participants ?? []).compactMap { UUID(uuidString: $0.studentID) }
    }
}
