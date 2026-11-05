// BlockingAlgorithmEngine+WorkCompletion.swift
// Whether a child's practice on the preceding lesson is done: which work rows
// gate her, and whether each is finished for her. Split from
// BlockingAlgorithmEngine.swift for SwiftLint's length limits.

import CoreData
import Foundation

extension BlockingAlgorithmEngine {

    /// Check if work is complete (either its status is closed OR all relevant participants have completedAt).
    ///
    /// - Parameters:
    ///   - work: The CDWorkModel to check
    ///   - requiredStudentIDs: The student IDs that need to have completed the work
    /// - Returns: True if work is complete for all required students
    nonisolated static func isWorkComplete(work: CDWorkModel, requiredStudentIDs: [UUID]) -> Bool {
        if work.status.isClosed {
            return true
        }

        let participantsArray = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        guard !participantsArray.isEmpty else {
            return false
        }

        let requiredStudentIDStrings = Set(requiredStudentIDs.map(\.uuidString))
        let relevantParticipants = participantsArray.filter { requiredStudentIDStrings.contains($0.studentID) }

        return !relevantParticipants.isEmpty && relevantParticipants.allSatisfy { $0.completedAt != nil }
    }

    /// Whether a work item applies to the given student: they are a participant, or —
    /// for legacy rows with no participants — the work's single-student field names them.
    static func workInvolvesStudent(work: CDWorkModel, studentID: UUID) -> Bool {
        let studentIDStr = studentID.uuidString
        let participantsArray = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        guard !participantsArray.isEmpty else {
            return work.studentID == studentIDStr
        }
        return participantsArray.contains { $0.studentID == studentIDStr }
    }

    /// The rows among one presentation's work that gate this child: the ones
    /// they own when they own any. Group work is usually one linked copy per
    /// child, each listing every classmate as a participant (see
    /// `WorkGrouping`), so a classmate's unfinished copy names this child
    /// too without being theirs. A child who owns none is gated by the rows
    /// that name them: a shared row, or a legacy row with no participants.
    static func gatingWork(for studentID: UUID, among works: [CDWorkModel]) -> [CDWorkModel] {
        let owned = works.filter { WorkGrouping.owner(of: $0) == studentID }
        return owned.isEmpty ? works.filter { workInvolvesStudent(work: $0, studentID: studentID) } : owned
    }

    /// Check if work is complete for a single student.
    static func isWorkCompleteForStudent(work: CDWorkModel, studentID: UUID) -> Bool {
        if work.status.isClosed {
            return true
        }

        let participantsArray = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        guard !participantsArray.isEmpty else {
            return false
        }

        let studentIDStr = studentID.uuidString
        guard let participant = participantsArray.first(where: { $0.studentID == studentIDStr }) else {
            return false
        }

        return participant.completedAt != nil
    }
}
