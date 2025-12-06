import Foundation

extension WorkModel {
    /// Prefer participants; fall back to legacy studentIDs during transition.
    var resolvedStudentIDs: [UUID] {
        let fromParticipants = participants.map { $0.studentID }
        if !fromParticipants.isEmpty { return fromParticipants }
        return studentIDs
    }

    /// Transition helper: keep legacy studentIDs in sync after mutating participants.
    func mirrorStudentIDsFromParticipants() {
        self.studentIDs = participants.map { $0.studentID }
    }
}
