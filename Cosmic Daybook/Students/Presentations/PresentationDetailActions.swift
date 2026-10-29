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
            // Note labels and history read the saved name first.
            if lessonChanged, lessonAssignment.lessonTitleSnapshot != nil {
                lessonAssignment.lessonTitleSnapshot = lesson.name
                lessonAssignment.lessonSectionSnapshot = lesson.section
            }
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
                if lessonChanged, let id = lessonAssignment.id {
                    WorkRepository(context: context).relinkOpenWork(
                        presentationID: id, toLesson: editingLessonID, lessons: lessons
                    )
                }
            }
        }
    }

    /// The lesson a split puts the children on: the one `source` is saved
    /// with, since the split saves at once while a Change Lesson waits for
    /// Save, and the entries that follow the children are for the saved one.
    /// A new presentation has no saved lesson yet, so it takes `edited`.
    static func splitLesson(
        for source: CDLessonAssignment, edited: CDLesson?, lessons: [CDLesson]
    ) -> CDLesson? {
        source.lesson ?? lessons.first { $0.id == source.resolvedLessonID } ?? edited
    }

    // Puts `studentsToMove` on a plan of their own for `currentLesson` (an
    // undated draft with exactly them, reused when one exists) and takes them
    // off `source`. Their year-plan entries promoted into `source`, and the
    // notes about only them, follow them to it. A plan the split would leave
    // with no saved child keeps `keepOnSource` (the open sheet's other
    // children) instead, since Cancel throws an empty plan away, its notes
    // with it. Saving is the caller's.
    // swiftlint:disable:next function_parameter_count
    func moveStudentsToInbox(
        from source: CDLessonAssignment,
        currentLesson: CDLesson,
        studentsToMove: Set<UUID>,
        studentsAll: [CDStudent],
        lessonAssignmentsAll: [CDLessonAssignment],
        keepOnSource: Set<UUID> = [],
        context: NSManagedObjectContext
    ) -> PresentationSplit? {
        guard !studentsToMove.isEmpty else { return nil }

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

        let ids = Set(studentsToMove.map(\.uuidString))
        let entries = source.id.map {
            PresentationRecordCleanup.entries(promotedInto: $0.uuidString, studentIDs: ids, in: context)
        } ?? []
        let notes = PresentationRecordCleanup.ownNotes(of: ids, on: source)
        // A given presentation's history rows go with the move and can't come
        // back, so only a split of a plan not yet given can be undone.
        let canUndo = !source.isPresented
        let wereOnSource = studentsToMove.intersection(source.resolvedStudentIDs)
        PresentationRecordCleanup.moveStudents(ids, from: source, to: destination, notes: notes, in: context)
        let remaining = source.resolvedStudentIDs.filter { !studentsToMove.contains($0) }
        let keep = remaining.isEmpty && !wereOnSource.isEmpty && !source.isPresented
            ? studentsAll.compactMap(\.id).filter { keepOnSource.subtracting(studentsToMove).contains($0) }
            : []
        source.studentIDs = (remaining + keep).map(\.uuidString)

        return PresentationSplit(
            names: movedStudentNames,
            studentIDs: studentsToMove,
            wereOnSource: wereOnSource,
            keptOnSource: Set(keep),
            source: source,
            destination: destination,
            madeDestination: existing == nil,
            notes: notes,
            entries: entries,
            canUndo: canUndo
        )
    }

    /// Puts a split back as it was: the children who were saved on `source`
    /// on it again (one added in the open sheet goes back to the sheet only,
    /// the caller's, and one the split saved there comes off again), their
    /// entries and notes with them, and a plan the split made deleted.
    /// Returns false, changing nothing, when either plan has since been given
    /// or deleted. Saving is the caller's.
    @discardableResult
    func undoSplit(_ split: PresentationSplit, context: NSManagedObjectContext) -> Bool {
        let source = split.source
        let destination = split.destination
        guard split.canUndo, !source.isDeleted, !destination.isDeleted,
              !source.isPresented, !destination.isPresented,
              let sourceID = source.id?.uuidString else { return false }

        let kept = source.resolvedStudentIDs.filter { !split.keptOnSource.contains($0) }
        source.studentIDs = (kept + split.wereOnSource.subtracting(kept)).map(\.uuidString)
        for entry in split.entries where !entry.isDeleted {
            entry.promotedAssignmentID = sourceID
        }
        PresentationRecordCleanup.moveNotes(
            from: destination, to: source,
            only: split.notes.filter { !$0.isDeleted && $0.lessonAssignment == destination }
        )
        if split.madeDestination {
            let rest = destination.resolvedStudentIDs.filter { !split.studentIDs.contains($0) }
            let hasNotes = !((destination.unifiedNotes as? Set<CDNote>) ?? []).filter { !$0.isDeleted }.isEmpty
            if rest.isEmpty && !hasNotes {
                context.delete(destination)
            } else {
                destination.studentIDs = rest.map(\.uuidString)
            }
        }
        return true
    }
}

/// What one split did, so its message's Undo can put it back.
struct PresentationSplit {
    let names: [String]
    let studentIDs: Set<UUID>
    /// Those of `studentIDs` saved on `source` when it was split; the rest
    /// had only been added in the open sheet.
    let wereOnSource: Set<UUID>
    /// Children of the open sheet the split saved on `source` so it kept one.
    let keptOnSource: Set<UUID>
    let source: CDLessonAssignment
    let destination: CDLessonAssignment
    /// The split made `destination`, rather than reusing a draft that had
    /// exactly these children.
    let madeDestination: Bool
    let notes: [CDNote]
    let entries: [CDYearPlanEntry]
    let canUndo: Bool
}
