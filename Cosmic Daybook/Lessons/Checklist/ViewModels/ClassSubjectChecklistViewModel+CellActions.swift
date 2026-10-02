// ClassAreaChecklistViewModel+CellActions.swift
// Individual cell toggle/mark/clear operations for ClassAreaChecklistViewModel.

import Foundation
import CoreData

extension ClassAreaChecklistViewModel {

    // MARK: - Entry Point

    /// The grid's one way in for a cell: finds the cell's student and lesson and runs the action.
    /// The actions that open a sheet or another screen belong to the grid and do nothing here.
    func perform(_ action: ChecklistCellAction, on cell: CellIdentifier, context: NSManagedObjectContext) {
        guard !performWithoutRecords(action, on: cell, context: context),
              let change = recordChange(for: action),
              let student = rosterStudents.first(where: { $0.id == cell.studentID }),
              let lesson = lessons.first(where: { $0.id == cell.lessonID })
        else { return }
        commitCellAction(action, lesson: lesson, context: context) {
            change(student, lesson, context)
        }
    }

    /// Clicks, the card and the selection: no records change. True when handled.
    private func performWithoutRecords(
        _ action: ChecklistCellAction, on cell: CellIdentifier, context: NSManagedObjectContext
    ) -> Bool {
        switch action {
        case .click:
            handleClick(cell, kind: .plain, studentOrder: students.compactMap(\.id), context: context)
        case .closeCard:
            // A card moving to another cell closes the old one's popover; leave the new open.
            if cardCell == cell { closeCard() }
        case .toggleSelection:
            selectedCells = ChecklistSelection.toggling(cell, in: selectedCells)
            selectionAnchor = cell
        case .present, .assignWork, .openLesson, .openStudent:
            break
        default:
            return false
        }
        return true
    }

    /// The change behind each action that writes records, without its save or refresh.
    private func recordChange(
        for action: ChecklistCellAction
    ) -> ((CDStudent, CDLesson, NSManagedObjectContext) -> Void)? {
        switch action {
        case .toggleScheduled: return { self.toggleScheduledNoRecompute(student: $0, lesson: $1, context: $2) }
        case .togglePresented: return { self.togglePresentedNoRecompute(student: $0, lesson: $1, context: $2) }
        case .togglePreviouslyPresented:
            return { self.togglePreviouslyPresentedNoRecompute(student: $0, lesson: $1, context: $2) }
        case .markPresented: return { self.markPresentedNoRecompute(student: $0, lesson: $1, context: $2) }
        case .markPracticing:
            return { self.markWorkNoRecompute(.active, student: $0, lesson: $1, context: $2) }
        case .markReviewing:
            return { self.markWorkNoRecompute(.review, student: $0, lesson: $1, context: $2) }
        case .markComplete: return { self.markCompleteNoRecompute(student: $0, lesson: $1, context: $2) }
        case .clearStatus: return { self.clearStatusNoRecompute(student: $0, lesson: $1, context: $2) }
        default: return nil
        }
    }

    /// Runs one cell's change, saves, and refreshes only the rows it can reach, inside a
    /// "Cell action" signpost interval (click → matrix updated).
    private func commitCellAction(
        _ action: ChecklistCellAction,
        lesson: CDLesson,
        context: NSManagedObjectContext,
        change: () -> Void
    ) {
        let signpost = ChecklistSignposts.beginCellAction(action.rawValue)
        defer { ChecklistSignposts.endCellAction(signpost) }
        change()
        context.safeSave()
        if let lessonID = lesson.id {
            refreshRows(touching: lessonID, context: context)
        } else {
            recomputeMatrix(context: context)
        }
        if cardCell?.lessonID == lesson.id { refreshCardRecord(context: context) }
    }

    // MARK: - Individual Cell Actions

    func toggleScheduled(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        commitCellAction(.toggleScheduled, lesson: lesson, context: context) {
            toggleScheduledNoRecompute(student: student, lesson: lesson, context: context)
        }
    }

    func toggleScheduledNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let lessonUUID = lesson.id, let studentUUID = student.id else { return }
        let lessonIDString = lessonUUID.uuidString
        let studentIDString = studentUUID.uuidString

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        let allLAs = context.safeFetch(request)

        if let existing = findUnscheduledLessonContaining(student: studentIDString, in: allLAs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
        } else {
            addStudentToUnscheduledLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
        }
    }

    func findUnscheduledLessonContaining(student: String, in lessons: [CDLessonAssignment]) -> CDLessonAssignment? {
        lessons.first(where: { !$0.isPresented && $0.studentIDs.contains(student) })
    }

    func removeStudentFromLesson(student: String, lesson: CDLessonAssignment, context: NSManagedObjectContext) {
        var ids = lesson.studentIDs
        ids.removeAll { $0 == student }
        if ids.isEmpty {
            context.delete(lesson)
        } else {
            lesson.studentIDs = ids
        }
    }

    func addStudentToUnscheduledLesson(
        student: CDStudent, studentIDString: String, lesson: CDLesson,
        in allLAs: [CDLessonAssignment], context: NSManagedObjectContext
    ) {
        if let sequence = allLAs.first(where: { !$0.isPresented && $0.scheduledFor == nil }) {
            if !sequence.studentIDs.contains(studentIDString) {
                sequence.studentIDs.append(studentIDString)
            }
        } else {
            guard let lessonID = lesson.id, let studentID = student.id else { return }
            _ = PresentationFactory.makeDraft(
                lessonID: lessonID,
                studentIDs: [studentID],
                context: context
            )
        }
    }

    func markComplete(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        commitCellAction(.markComplete, lesson: lesson, context: context) {
            markCompleteNoRecompute(student: student, lesson: lesson, context: context)
        }
    }

    func markCompleteNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let studentUUID = student.id, let lessonUUID = lesson.id else { return }
        let studentIDString = studentUUID.uuidString
        let lessonIDString = lessonUUID.uuidString

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        let allLAs = context.safeFetch(request)
        if findGivenLessonContaining(student: studentIDString, in: allLAs) == nil {
            addStudentToGivenLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
        }

        findOrCreateWorkAndMarkComplete(student: student, lesson: lesson, context: context)

        upsertLessonPresentation(
            studentID: studentIDString, lessonID: lessonIDString,
            state: .proficient, context: context
        )
        SequenceTrackService.autoEnrollInTrackIfNeeded(
            lessonArea: lesson.area, lessonSequence: lesson.sequence, studentIDs: [studentIDString], context: context
        )
        SequenceTrackService.checkAndCompleteTrackIfNeeded(
            lessonArea: lesson.area, lessonSequence: lesson.sequence, studentID: studentIDString, context: context
        )
    }

    func togglePresented(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        commitCellAction(.togglePresented, lesson: lesson, context: context) {
            togglePresentedNoRecompute(student: student, lesson: lesson, context: context)
        }
    }

    func togglePresentedNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let studentUUID = student.id, let lessonUUID = lesson.id else { return }
        let studentIDString = studentUUID.uuidString
        let lessonIDString = lessonUUID.uuidString

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        let allLAs = context.safeFetch(request)

        if let existing = findGivenLessonContaining(student: studentIDString, in: allLAs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
            deleteLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString, context: context
            )
        } else {
            addStudentToGivenLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
            upsertLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString,
                state: .presented, context: context
            )
        }
    }

    func findGivenLessonContaining(student: String, in lessons: [CDLessonAssignment]) -> CDLessonAssignment? {
        lessons.first(where: { $0.isPresented && $0.studentIDs.contains(student) })
    }

    func addStudentToGivenLesson(
        student: CDStudent, studentIDString: String, lesson: CDLesson,
        in allLAs: [CDLessonAssignment], context: NSManagedObjectContext
    ) {
        let today = Date()
        let isGivenToday = { (la: CDLessonAssignment) -> Bool in
            la.isPresented && (la.presentedAt ?? Date.distantPast).isSameDay(as: today)
        }
        if let sequence = allLAs.first(where: isGivenToday) {
            if !sequence.studentIDs.contains(studentIDString) {
                sequence.studentIDs.append(studentIDString)
                SequenceTrackService.autoEnrollInTrackIfNeeded(
                    lessonArea: lesson.area,
                    lessonSequence: lesson.sequence,
                    studentIDs: [studentIDString],
                    context: context
                )
            }
        } else {
            guard let lessonUUID = lesson.id, let studentUUID = student.id else { return }
            _ = PresentationFactory.makePresented(
                lessonID: lessonUUID,
                studentIDs: [studentUUID],
                context: context
            )
            SequenceTrackService.autoEnrollInTrackIfNeeded(
                lessonArea: lesson.area,
                lessonSequence: lesson.sequence,
                studentIDs: [studentIDString],
                context: context
            )
        }
    }

    // MARK: - Previously Presented (Undated)

    func togglePreviouslyPresented(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        commitCellAction(.togglePreviouslyPresented, lesson: lesson, context: context) {
            togglePreviouslyPresentedNoRecompute(student: student, lesson: lesson, context: context)
        }
    }

    func togglePreviouslyPresentedNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let studentUUID = student.id, let lessonUUID = lesson.id else { return }
        let studentIDString = studentUUID.uuidString
        let lessonIDString = lessonUUID.uuidString

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        let allLAs = context.safeFetch(request)

        if let existing = findGivenLessonContaining(student: studentIDString, in: allLAs) {
            removeStudentFromLesson(student: studentIDString, lesson: existing, context: context)
            deleteLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString, context: context
            )
        } else {
            addStudentToUndatedLesson(
                student: student, studentIDString: studentIDString,
                lesson: lesson, in: allLAs, context: context
            )
            upsertLessonPresentation(
                studentID: studentIDString, lessonID: lessonIDString,
                state: .presented, context: context
            )
        }
    }

    func addStudentToUndatedLesson(
        student: CDStudent, studentIDString: String, lesson: CDLesson,
        in allLAs: [CDLessonAssignment], context: NSManagedObjectContext
    ) {
        let isUndatedPresented = { (la: CDLessonAssignment) -> Bool in
            la.isPresented && la.presentedAt == nil
        }
        if let sequence = allLAs.first(where: isUndatedPresented) {
            if !sequence.studentIDs.contains(studentIDString) {
                sequence.studentIDs.append(studentIDString)
                SequenceTrackService.autoEnrollInTrackIfNeeded(
                    lessonArea: lesson.area,
                    lessonSequence: lesson.sequence,
                    studentIDs: [studentIDString],
                    context: context
                )
            }
        } else {
            guard let lessonUUID = lesson.id, let studentUUID = student.id else { return }
            _ = PresentationFactory.makePreviouslyPresented(
                lessonID: lessonUUID,
                studentIDs: [studentUUID],
                context: context
            )
            SequenceTrackService.autoEnrollInTrackIfNeeded(
                lessonArea: lesson.area,
                lessonSequence: lesson.sequence,
                studentIDs: [studentIDString],
                context: context
            )
        }
    }

    func clearStatus(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        commitCellAction(.clearStatus, lesson: lesson, context: context) {
            clearStatusNoRecompute(student: student, lesson: lesson, context: context)
        }
    }

    func clearStatusNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let lid = lesson.id, let sid = student.id else { return }
        let sidString = sid.uuidString
        let lidString = lid.uuidString

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lidString)
        let las = context.safeFetch(request)
        for la in las where la.studentIDs.contains(sidString) {
            var newIDs = la.studentIDs
            newIDs.removeAll { $0 == sidString }
            if newIDs.isEmpty {
                PresentationRecordCleanup.prepareToDelete(la, in: context)
                context.delete(la)
            } else {
                PresentationRecordCleanup.removeStudents([sidString], from: la, in: context)
                la.studentIDs = newIDs
            }
        }

        // PERF: Filter by lessonID in predicate to avoid loading all non-complete work.
        // Take her off the rows rather than deleting every row that names her:
        // a shared row also carries the other children on it.
        let workRequest = CDFetchRequest(CDWorkModel.self)
        workRequest.predicate = NSPredicate(
            format: "statusRaw IN %@ AND lessonID == %@", WorkStatus.openRawValues, lidString
        )
        WorkDeletionService.removeWithoutSaving(
            studentID: sid, from: context.safeFetch(workRequest), in: context
        )

        deleteLessonPresentation(studentID: sidString, lessonID: lidString, context: context)
    }
}
