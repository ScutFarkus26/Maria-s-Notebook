import Foundation

extension WorkModel {
    /// Participants are the single source of truth for student membership.
    var resolvedStudentIDs: [UUID] {
        (participants ?? []).map { $0.studentID }
    }
}
