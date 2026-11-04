// ClassAreaChecklistViewModel+Removing.swift
// Unmark Presented and Remove Plan from a cell (menu, card): straight away, unless taking
// her off deletes a record that was given or carries notes (she was the only child on it).
// Then the change waits in `pendingRemoval` until the guide says yes, as Clear does
// (+Clearing, `ChecklistRemovalSummary`). Either way her notes stay hers
// (`ChecklistRosterRemoval.remove`).

import CoreData
import Foundation

extension ClassAreaChecklistViewModel {

    /// The question to ask before `action` runs on `cell`, or nil when it can run now: it
    /// adds her, takes her off a group, or deletes a plain plan with nothing on it.
    func removalNeedingConfirmation(
        _ action: ChecklistCellAction, on cell: CellIdentifier, context: NSManagedObjectContext
    ) -> ChecklistRemovalRequest? {
        guard let record = recordToTakeOff(action, cell: cell, context: context),
              let summary = ChecklistRosterRemoval.removalSummary(
                  of: cell.studentID.uuidString, from: record, in: context
              ),
              summary.needsConfirmation
        else { return nil }
        return ChecklistRemovalRequest(
            cell: cell,
            action: action,
            summary: summary,
            childName: rosterStudents.first { $0.id == cell.studentID }?.shortName,
            lessonName: lessons.first { $0.id == cell.lessonID }?.name
        )
    }

    /// The guide said yes: takes her off the record she is on now. If she is on none any
    /// more (another device took her off meanwhile), nothing changes; the toggle never
    /// turns into an add here.
    func confirmRemoval(_ request: ChecklistRemovalRequest, context: NSManagedObjectContext) {
        pendingRemoval = nil
        guard let lesson = lessons.first(where: { $0.id == request.cell.lessonID }) else { return }
        commitCellAction(request.action, lesson: lesson, context: context) {
            guard let record = recordToTakeOff(request.action, cell: request.cell, context: context) else { return }
            let studentKey = request.cell.studentID.uuidString
            if request.action == .toggleScheduled {
                removeStudentFromLesson(student: studentKey, lesson: record, context: context)
            } else {
                unmarkPresented(
                    student: studentKey, lessonID: request.cell.lessonID.uuidString,
                    from: record, among: assignments(of: request.cell.lessonID, context: context),
                    context: context
                )
            }
        }
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    /// The presentation (for the Presented toggles) or plan (for the Inbox toggle) the
    /// action would take her off, by the toggles' own lookups; nil when it would add her.
    private func recordToTakeOff(
        _ action: ChecklistCellAction, cell: CellIdentifier, context: NSManagedObjectContext
    ) -> CDLessonAssignment? {
        let studentKey = cell.studentID.uuidString
        switch action {
        case .togglePresented, .togglePreviouslyPresented:
            return findGivenLessonContaining(student: studentKey, in: assignments(of: cell.lessonID, context: context))
        case .toggleScheduled:
            return findUnscheduledLessonContaining(
                student: studentKey, in: assignments(of: cell.lessonID, context: context)
            )
        default:
            return nil
        }
    }

    private func assignments(of lessonID: UUID, context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        return context.safeFetch(request).filter { !$0.isDeleted }
    }
}
