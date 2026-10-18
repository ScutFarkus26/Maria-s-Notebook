import Foundation
import OSLog
import CoreData

// MARK: - Checklist Batch Action Executor

/// Executes batch operations on checklist cells.
/// Handles adding to inbox, marking presented/mastered, and clearing status.
enum ChecklistBatchActionExecutor {
    private static let logger = Logger.lessons

    // MARK: - Batch Add to Inbox

    /// Adds selected cells to inbox (creates draft LessonAssignments).
    static func batchAddToInbox(
        selectedCells: Set<CellIdentifier>,
        students: [CDStudent],
        lessons: [CDLesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: NSManagedObjectContext
    ) {
        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            // Only add if not already scheduled
            if state?.isScheduled != true {
                toggleScheduledNoRecompute(student: student, lesson: lesson, context: context)
            }
        }
        context.safeSave()
    }

    // MARK: - Batch Mark Presented

    /// Marks selected cells as presented. Only ever adds: a cell the grid
    /// drew as not presented may have been given on another device since, and
    /// a batch mark must not take her off it (bug hunt 2026-10-17 #48).
    static func batchMarkPresented(
        selectedCells: Set<CellIdentifier>,
        students: [CDStudent],
        lessons: [CDLesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: NSManagedObjectContext
    ) {
        // Pre-fetch all LessonPresentations once for upsert operations
        let allLPs = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))

        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            if state?.isPresented != true {
                markPresentedNoRecompute(
                    student: student, lesson: lesson, attachment: .today,
                    prefetchedLPs: allLPs, context: context
                )
            }
        }
        context.safeSave()
    }

    // MARK: - Batch Mark Previously Presented

    /// Marks selected cells as previously presented (undated). Only ever adds,
    /// as `batchMarkPresented` does.
    static func batchMarkPreviouslyPresented(
        selectedCells: Set<CellIdentifier>,
        students: [CDStudent],
        lessons: [CDLesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: NSManagedObjectContext
    ) {
        let allLPs = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))

        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            if state?.isPresented != true {
                markPresentedNoRecompute(
                    student: student, lesson: lesson, attachment: .undated,
                    prefetchedLPs: allLPs, context: context
                )
            }
        }
        context.safeSave()
    }

    // MARK: - Batch Mark Mastered

    /// Marks selected cells as mastered. A cell already carrying a mastery mark is skipped;
    /// every other one is marked, Reviewing ones included. (The gate used to be closed work,
    /// so a cell whose work had closed without a mark could never be marked from here.)
    static func batchMarkProficient(
        selectedCells: Set<CellIdentifier>,
        students: [CDStudent],
        lessons: [CDLesson],
        matrixStates: [UUID: [UUID: StudentChecklistRowState]],
        context: NSManagedObjectContext
    ) {
        let allLPs = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))

        for cell in selectedCells {
            guard let student = students.first(where: { $0.id == cell.studentID }),
                  let lesson = lessons.first(where: { $0.id == cell.lessonID }) else { continue }
            let state = matrixStates[cell.studentID]?[cell.lessonID]
            if state?.isMastered != true {
                markCompleteNoRecompute(
                    student: student, lesson: lesson,
                    prefetchedLPs: allLPs,
                    context: context
                )
            }
        }
        context.safeSave()
    }

    // MARK: - Batch Clear Status

    /// Clears the selected cells by the same rule as a cell's own Clear
    /// (`ChecklistCellRecords.clear`).
    static func batchClearStatus(
        selectedCells: Set<CellIdentifier>,
        students: [CDStudent],
        lessons: [CDLesson],
        context: NSManagedObjectContext
    ) {
        for cell in selectedCells {
            guard students.contains(where: { $0.id == cell.studentID }),
                  lessons.contains(where: { $0.id == cell.lessonID }) else { continue }
            ChecklistCellRecords.clear(studentID: cell.studentID, lessonID: cell.lessonID, in: context)
        }
        context.safeSave()
    }

    // MARK: - Private Helpers

    private static func toggleScheduledNoRecompute(
        student: CDStudent,
        lesson: CDLesson,
        context: NSManagedObjectContext
    ) {
        let lessonIDString = lesson.id?.uuidString ?? ""
        let studentIDString = student.cloudKitKey

        let laRequest = CDFetchRequest(CDLessonAssignment.self)
        laRequest.predicate = NSPredicate(format: "lessonID == %@", lessonIDString as CVarArg)
        let allLAs = context.safeFetch(laRequest)

        if let existing = allLAs.first(where: {
            !$0.isPresented && $0.studentIDs.contains(studentIDString)
        }) {
            ChecklistRosterRemoval.remove(studentIDString, from: existing, in: context)
        } else {
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
    }

    /// Puts one child on a presentation of one lesson, unless one already
    /// names her. Never takes her off one: the cell's own toggle does that,
    /// and a batch reads the grid as drawn, which may be stale.
    ///
    /// `attachment` is the whole difference between *Presented* and *Previously
    /// Presented* — see `PresentedAttachment`.
    private static func markPresentedNoRecompute(
        student: CDStudent, lesson: CDLesson,
        attachment: PresentedAttachment,
        prefetchedLPs: [CDLessonPresentation],
        context: NSManagedObjectContext
    ) {
        let studentIDString = student.cloudKitKey
        let lessonIDString = lesson.id?.uuidString ?? ""

        let laRequest = CDFetchRequest(CDLessonAssignment.self)
        laRequest.predicate = NSPredicate(format: "lessonID == %@", lessonIDString as CVarArg)
        let allLAs = context.safeFetch(laRequest)

        guard !allLAs.contains(where: { $0.isPresented && $0.studentIDs.contains(studentIDString) }) else {
            return
        }
        addStudentToPresentedLesson(
            student: student, lesson: lesson,
            in: allLAs, attachment: attachment, context: context
        )
        upsertLessonPresentation(
            studentID: studentIDString, lessonID: lessonIDString,
            state: .presented, from: prefetchedLPs, context: context
        )
    }

    private static func markCompleteNoRecompute(
        student: CDStudent, lesson: CDLesson,
        prefetchedLPs: [CDLessonPresentation],
        context: NSManagedObjectContext
    ) {
        let studentIDString = student.cloudKitKey
        let lessonIDString = lesson.id?.uuidString ?? ""

        let laRequest = CDFetchRequest(CDLessonAssignment.self)
        laRequest.predicate = NSPredicate(format: "lessonID == %@", lessonIDString as CVarArg)
        let allLAs = context.safeFetch(laRequest)
        if allLAs.first(where: { $0.isPresented && $0.studentIDs.contains(studentIDString) }) == nil {
            addStudentToPresentedLesson(
                student: student, lesson: lesson,
                in: allLAs, attachment: .today, context: context
            )
        }

        if let studentID = student.id, let lessonID = lesson.id {
            ChecklistCellRecords.closeWorkForMastery(studentID: studentID, lessonID: lessonID, in: context)
        }

        upsertLessonPresentation(
            studentID: studentIDString, lessonID: lessonIDString,
            state: .proficient, from: prefetchedLPs, context: context
        )

        SequenceTrackService.autoEnrollInTrackIfNeeded(
            lessonArea: lesson.area, lessonSequence: lesson.sequence,
            studentIDs: [studentIDString], context: context
        )
        SequenceTrackService.checkAndCompleteTrackIfNeeded(
            lessonArea: lesson.area, lessonSequence: lesson.sequence,
            studentID: studentIDString, context: context
        )
    }

    /// Puts the child on the presented row `attachment` describes, creating it
    /// when the context has none.
    private static func addStudentToPresentedLesson(
        student: CDStudent,
        lesson: CDLesson,
        in allLAs: [CDLessonAssignment],
        attachment: PresentedAttachment,
        context: NSManagedObjectContext
    ) {
        let studentIDString = student.cloudKitKey
        let today = Date()
        if let sequence = allLAs.first(where: { attachment.matches($0, today: today) }) {
            if !sequence.studentIDs.contains(studentIDString) {
                sequence.studentIDs.append(studentIDString)
                SequenceTrackService.autoEnrollInTrackIfNeeded(
                    lessonArea: lesson.area, lessonSequence: lesson.sequence,
                    studentIDs: [studentIDString], context: context
                )
            }
        } else {
            guard let lessonID = lesson.id, let studentID = student.id else { return }
            _ = attachment.makeAssignment(lessonID: lessonID, studentID: studentID, context: context)
            SequenceTrackService.autoEnrollInTrackIfNeeded(
                lessonArea: lesson.area, lessonSequence: lesson.sequence,
                studentIDs: [studentIDString], context: context
            )
        }
    }

    static func upsertLessonPresentation(
        studentID: String,
        lessonID: String,
        state: LessonPresentationState,
        from prefetchedLPs: [CDLessonPresentation],
        context: NSManagedObjectContext
    ) {
        // Filter from pre-fetched data instead of re-fetching all LessonPresentations
        let existing = prefetchedLPs.first { lp in
            lp.studentID == studentID && lp.lessonID == lessonID
        }

        if let existing {
            if state == .proficient && existing.state != .proficient {
                existing.state = .proficient
                existing.masteredAt = Date()
            }
            existing.lastObservedAt = Date()
        } else {
            let lp = CDLessonPresentation(context: context)
            lp.studentID = studentID
            lp.lessonID = lessonID
            lp.state = state
            lp.presentedAt = Date()
            lp.lastObservedAt = Date()
            lp.masteredAt = state == .proficient ? Date() : nil
        }
    }

}
