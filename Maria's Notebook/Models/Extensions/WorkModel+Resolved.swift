import Foundation

extension CDWorkModel {
    /// Participants are the single source of truth for student membership.
    var resolvedStudentIDs: [UUID] {
        // CloudKit compatibility: Convert String IDs to UUIDs
        ((participants?.allObjects as? [CDWorkParticipantEntity]) ?? []).compactMap { UUID(uuidString: $0.studentID) }
    }
}
