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

    /// The rows among one presentation's work that gate this child: her work,
    /// by the one ownership rule (`WorkOwnership`). Group work is usually one
    /// linked copy per child, each listing every classmate as a participant,
    /// so a classmate's unfinished copy names this child too without being
    /// hers; a shared row she is on gates her until her own part is done.
    /// This used to be a rule of its own, which dropped a shared row beside
    /// her own work and, for a child who owned nothing, counted a classmate's
    /// copy (domain logic review 2026-11-20, R22).
    static func gatingWork(for studentID: UUID, among works: [CDWorkModel]) -> [CDWorkModel] {
        guard let context = works.lazy.compactMap(\.managedObjectContext).first else {
            return works.filter { WorkGrouping.owner(of: $0) == studentID }
        }
        let ownership = WorkOwnership.Reader(covering: works, in: context)
        return works.filter { ownership.isWork($0, of: studentID) }
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
