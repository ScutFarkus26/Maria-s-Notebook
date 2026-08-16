import Foundation
import SwiftUI
import CoreData

@Observable
@MainActor
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

        lessonAssignment.lessonID = editingLessonID.uuidString
        lessonAssignment.notes = notes
        lessonAssignment.needsAnotherPresentation = needsAnotherPresentation
        lessonAssignment.studentIDs = selectedStudentIDs.map(\.uuidString)
        lessonAssignment.lesson = lessons.first(where: { $0.id == editingLessonID })

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
    }

    func moveStudentsToInbox(
        currentLesson: CDLesson,
        studentsToMove: Set<UUID>,
        studentsAll: [CDStudent],
        lessonAssignmentsAll: [CDLessonAssignment],
        context: NSManagedObjectContext
    ) -> [String] {
        guard !studentsToMove.isEmpty else { return [] }

        let movedStudentNames = studentsAll
            .filter { guard let sid = $0.id else { return false }; return studentsToMove.contains(sid) }
            .map { StudentFormatter.displayName(for: $0) }

        let currentLessonID = currentLesson.id ?? UUID()
        let targetSet = studentsToMove
        let existing = lessonAssignmentsAll.first(where: { la in
            la.resolvedLessonID == currentLessonID && la.scheduledFor == nil
                && !la.isPresented && Set(la.resolvedStudentIDs) == targetSet
        })

        if let ex = existing {
            ex.studentIDs = studentsAll.compactMap(\.id).filter { targetSet.contains($0) }.map(\.uuidString)
            ex.lesson = currentLesson
        } else {
            let newLA = PresentationFactory.makeDraft(
                lesson: currentLesson,
                students: studentsAll.filter {
                    guard let sid = $0.id else { return false }
                    return targetSet.contains(sid)
                },
                context: context
            )
            _ = newLA // Core Data auto-inserts into context
        }

        context.safeSave()
        PresentationDetailUtilities.notifyInboxRefresh()
        return movedStudentNames
    }

}
