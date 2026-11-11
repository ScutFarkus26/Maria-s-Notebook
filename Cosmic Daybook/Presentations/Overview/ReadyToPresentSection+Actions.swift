// ReadyToPresentSection+Actions.swift
// What the backlog's buttons do: schedule a selection today, unlock a brewing
// lesson, and move a brewing lesson's ready children into a presentation of
// their own.

import CoreData
import SwiftUI

extension ReadyToPresentSection {

    /// Puts every selected presentation on today, spaced the way a drop onto
    /// today's column would space them: morning slots from 9:00, which stop at
    /// the last slot rank so a long selection never reads as a set time.
    func scheduleSelectionToday() {
        let selected = currentlyVisibleAssignments.filter { selection.contains($0.id) }
        guard !selected.isEmpty else { return }

        let today = AppCalendar.startOfDay(Date())
        for (index, assignment) in selected.enumerated() {
            let slot = DayHalfPlanner.slot(
                index * UIConstants.scheduleSpacingSeconds, in: .morning, on: today, using: AppCalendar.shared
            )
            assignment.setScheduledFor(slot, using: AppCalendar.shared)
        }
        if viewContext.safeSave() {
            selection.clear()
        }
    }

    func unlockBrewingLesson(_ la: CDLessonAssignment) {
        guard !la.manuallyUnblocked, let ctx = la.managedObjectContext else { return }
        la.manuallyUnblocked = true
        la.modifiedAt = Date()
        ctx.safeSave()
    }

    func splitReadyToInbox(_ la: CDLessonAssignment, result: BlockingAlgorithmEngine.BlockingCheckResult) {
        let readyIDs = result.readyStudentIDs
        guard !readyIDs.isEmpty else { return }

        guard let ctx = la.managedObjectContext else { return }
        PresentationSplitService.splitReadyStudents(
            from: la,
            readyStudentIDs: readyIDs,
            asDraft: true,
            context: ctx
        )
        ctx.safeSave()
    }
}
