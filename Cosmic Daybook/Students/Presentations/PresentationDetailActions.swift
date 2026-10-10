import Foundation
import SwiftUI
import CoreData

@Observable
final class PresentationDetailActions {
    // swiftlint:disable:next function_parameter_count
    func applyEditsToModel(
        lessonAssignment: CDLessonAssignment,
        editingLessonID: UUID,
        scheduledFor: Date?,
        givenAt: Date?,
        isPresented: Bool,
        notes: String,
        needsAnotherPresentation: Bool,
        selectedStudentIDs: Set<UUID>,
        studentsAll: [CDStudent],
        lessons: [CDLesson],
        calendar: Calendar
    ) {
        // Do not allow zero-student lessons; skip applying edits if empty selection
        guard !selectedStudentIDs.isEmpty else { return }

        let wasPresented = lessonAssignment.isPresented
        let removedStudentIDs = Set(lessonAssignment.studentIDs)
            .subtracting(selectedStudentIDs.map(\.uuidString))
        let lessonChanged = lessonAssignment.lessonID != editingLessonID.uuidString

        lessonAssignment.lessonID = editingLessonID.uuidString
        if lessonChanged {
            // The track and step named the old lesson; recording works them
            // out again for the new one.
            lessonAssignment.trackID = nil
            lessonAssignment.trackStepID = nil
        }
        lessonAssignment.notes = notes
        lessonAssignment.needsAnotherPresentation = needsAnotherPresentation
        lessonAssignment.studentIDs = selectedStudentIDs.map(\.uuidString)
        if let lesson = lessons.first(where: { $0.id == editingLessonID }) {
            lessonAssignment.lesson = lesson
        }

        // State transitions: presented > scheduled > draft
        if isPresented {
            if let givenAt {
                lessonAssignment.markPresented(at: calendar.startOfDay(for: givenAt))
            } else {
                lessonAssignment.markPreviouslyPresented()
            }
        } else {
            if lessonAssignment.state == .presented {
                lessonAssignment.presentedAt = nil
            }
            lessonAssignment.setScheduledFor(scheduledFor, using: calendar)
        }

        // The history rows and promoted entries hang off this presentation by
        // id, so they follow the edit here or read as given for good.
        if let context = lessonAssignment.managedObjectContext {
            PresentationRecordCleanup.removeStudents(removedStudentIDs, from: lessonAssignment, in: context)
            if lessonChanged {
                PresentationRecordCleanup.returnEntriesForOtherLessons(promotedInto: lessonAssignment, in: context)
            }
            if wasPresented && !lessonAssignment.isPresented {
                PresentationRecordCleanup.unmarkPresented(lessonAssignment, in: context)
            } else if lessonAssignment.isPresented {
                // Change Lesson on a given presentation: the children's
                // history rows move to the new lesson with it, so the year
                // plan and the regive guard read the lesson she was given.
                LifecycleService.relinkHistoryRows(of: lessonAssignment, in: context)
            }
        }
    }

    // Puts `studentsToMove` on a plan of their own for `currentLesson` (an
    // undated draft with exactly them, reused when one exists). Their
    // year-plan entries promoted into `source` follow them to it; taking
    // them off `source` is the caller's.
    // swiftlint:disable:next function_parameter_count
    func moveStudentsToInbox(
        from source: CDLessonAssignment,
        currentLesson: CDLesson,
        studentsToMove: Set<UUID>,
        studentsAll: [CDStudent],
        lessonAssignmentsAll: [CDLessonAssignment],
        context: NSManagedObjectContext
    ) -> [String] {
        guard !studentsToMove.isEmpty else { return [] }

        let movedStudentNames = studentsAll
            .filter { guard let sid = $0.id else { return false }; return studentsToMove.contains(sid) }
            .map { $0.shortName }

        let currentLessonID = currentLesson.id ?? UUID()
        let targetSet = studentsToMove
        let existing = lessonAssignmentsAll.first(where: { la in
            la.objectID != source.objectID && la.resolvedLessonID == currentLessonID && la.scheduledFor == nil
                && !la.isPresented && Set(la.resolvedStudentIDs) == targetSet
        })

        let destination: CDLessonAssignment
        if let ex = existing {
            ex.studentIDs = studentsAll.compactMap(\.id).filter { targetSet.contains($0) }.map(\.uuidString)
            ex.lesson = currentLesson
            destination = ex
        } else {
            destination = PresentationFactory.makeDraft(
                lesson: currentLesson,
                students: studentsAll.filter {
                    guard let sid = $0.id else { return false }
                    return targetSet.contains(sid)
                },
                context: context
            )
        }
        PresentationRecordCleanup.moveStudents(
            Set(studentsToMove.map(\.uuidString)), from: source, to: destination, in: context
        )

        context.safeSave()
        PresentationDetailUtilities.notifyInboxRefresh()
        return movedStudentNames
    }

}
