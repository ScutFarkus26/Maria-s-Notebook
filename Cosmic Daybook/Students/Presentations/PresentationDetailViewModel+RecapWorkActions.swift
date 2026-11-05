// PresentationDetailViewModel+RecapWorkActions.swift
// Recap-driven work actions: create a CDWorkModel from inside the sequence recap,
// cycle a work's status, and recompute the recap so the UI reflects the change.

import Foundation
import CoreData
import OSLog

extension PresentationDetailViewModel {

    static let recapWorkNotAddedMessage = "Couldn't add the work. Try again."
    static let recapStatusNotChangedMessage = "Couldn't change the work's status. Try again."
    static let recapWorkGoneMessage = "That work isn't in the notebook anymore, so its status can't change."

    /// Creates a new CDWorkModel for `(studentID, lessonID)` and opens its detail sheet.
    /// `presentationID` is the CDLessonAssignment that spawned this work, or nil for
    /// follow-up work that isn't tied to a specific presentation.
    ///
    /// A failure says so (`recapActionMessage`); it used to be only logged, so
    /// the button looked as if it did nothing (bug hunt 2026-11-03, Smaller).
    func addRecapWork(
        lessonID: UUID,
        studentID: UUID,
        presentationID: UUID?,
        currentLesson: CDLesson?,
        students: [CDStudent]
    ) {
        let repo = WorkRepository(context: viewContext)
        do {
            let work = try repo.createWork(
                studentID: studentID,
                lessonID: lessonID,
                kind: .practiceLesson,
                presentationID: presentationID
            )
            if let id = work.id {
                recapWorkSheetID = id
            }
            recomputeSequenceRecap(currentLesson: currentLesson, students: students)
        } catch {
            Self.logger.warning("addRecapWork: failed to create work: \(error.localizedDescription)")
            recapActionMessage = Self.recapWorkFailureMessage(
                for: error, student: students.first { $0.id == studentID }
            )
        }
    }

    /// The plain sentence for a work the recap couldn't add: her name when she
    /// has left the class, the general one otherwise.
    static func recapWorkFailureMessage(for error: Error, student: CDStudent?) -> String {
        if case .studentNotEnrolled(let name, _) = error as? WorkRepository.AssignmentError {
            return "\(student?.shortName ?? name) has left the class, so they can't get new work."
        }
        return recapWorkNotAddedMessage
    }

    /// Cycles a CDWorkModel's status. A closing status goes through
    /// `WorkLogService` as the repository's `markWorkCompleted` does, so
    /// `completedAt` is stamped and readiness auto-unlock runs; called here
    /// directly so a failure can be shown rather than only logged.
    func cycleRecapWorkStatus(
        workID: UUID,
        to status: WorkStatus,
        currentLesson: CDLesson?,
        students: [CDStudent]
    ) {
        defer { recomputeSequenceRecap(currentLesson: currentLesson, students: students) }
        guard let work = viewContext.object(CDWorkModel.self, id: workID), !work.isDeleted else {
            recapActionMessage = Self.recapWorkGoneMessage
            return
        }
        do {
            try WorkLogService.log([.init(work: work, status: status, note: nil)], context: viewContext)
            if status.isClosed { HapticService.shared.notification(.success) }
        } catch {
            Self.logger.error("cycleRecapWorkStatus: failed to log work status \(workID): \(error)")
            recapActionMessage = Self.recapStatusNotChangedMessage
        }
    }
}
