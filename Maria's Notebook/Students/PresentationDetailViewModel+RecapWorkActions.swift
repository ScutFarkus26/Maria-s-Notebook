// PresentationDetailViewModel+RecapWorkActions.swift
// Recap-driven work actions: create a CDWorkModel from inside the sequence recap,
// cycle a work's status, and recompute the recap so the UI reflects the change.

import Foundation
import CoreData
import OSLog

extension PresentationDetailViewModel {

    /// Creates a new CDWorkModel for `(studentID, lessonID)` and opens its detail sheet.
    /// `presentationID` is the CDLessonAssignment that spawned this work, or nil for
    /// follow-up work that isn't tied to a specific presentation.
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
        }
    }

    /// Cycles a CDWorkModel's status. When transitioning to `.complete`, routes through
    /// `markWorkCompleted` so `completedAt` is stamped and readiness auto-unlock runs.
    func cycleRecapWorkStatus(
        workID: UUID,
        to status: WorkStatus,
        currentLesson: CDLesson?,
        students: [CDStudent]
    ) {
        let repo = WorkRepository(context: viewContext)
        if status == .complete {
            repo.markWorkCompleted(id: workID, outcome: nil, note: nil)
        } else {
            repo.updateWorkStatus(id: workID, status: status)
        }
        recomputeSequenceRecap(currentLesson: currentLesson, students: students)
    }
}
