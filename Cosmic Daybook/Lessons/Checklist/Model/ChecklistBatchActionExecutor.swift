import Foundation
import OSLog
import CoreData

// MARK: - Checklist Batch Action Executor

/// Executes batch operations on checklist cells.
/// Handles adding to inbox, marking presented/mastered, and clearing status.
/// None of these saves: the view model saves once for the whole selection and takes
/// the change back if the save fails (`saveChange`, bug hunt 2026-11-03 #13).
enum ChecklistBatchActionExecutor {
    private static let logger = Logger.lessons

    // MARK: - Batch Add to Inbox

    /// Adds selected cells to inbox (creates draft LessonAssignments). Only ever adds: a
    /// child the grid drew as unplanned may have been planned on another device since,
    /// and the selection must not take her off that plan (bug hunt 2026-11-03 #10).
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
                addToInbox(student: student, lesson: lesson, context: context)
            }
        }
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
    }

    // MARK: - Private Helpers

    /// Puts the child on the lesson's Inbox draft, or a new one, unless a plan already
    /// names her. Never takes her off one: the cell's own toggle does that.
    private static func addToInbox(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        let lessonIDString = lesson.id?.uuidString ?? ""
        let studentIDString = student.cloudKitKey

        let laRequest = CDFetchRequest(CDLessonAssignment.self)
        laRequest.predicate = NSPredicate(format: "lessonID == %@", lessonIDString as CVarArg)
        let allLAs = context.safeFetch(laRequest).filter { !$0.isDeleted }

        guard !allLAs.contains(where: { !$0.isPresented && $0.studentIDs.contains(studentIDString) }),
              let studentID = student.id else { return }
        let plan: CDLessonAssignment
        if let sequence = allLAs.first(where: { !$0.isPresented && $0.scheduledFor == nil }) {
            sequence.studentIDs.append(studentIDString)
            plan = sequence
        } else {
            guard let lessonID = lesson.id else { return }
            plan = PresentationFactory.makeDraft(
                lessonID: lessonID,
                studentIDs: [studentID],
                context: context
            )
        }
        // The plan answers her year-plan entry, as the cell's own toggle does.
        YearPlanPromotionService.promoteMatchingEntry(for: studentID, into: plan, context: context)
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
        let given = addStudentToPresentedLesson(
            student: student, lesson: lesson,
            in: allLAs, attachment: attachment, context: context
        )
        upsertLessonPresentation(
            studentID: studentIDString, lessonID: lessonIDString,
            state: .presented, from: prefetchedLPs, givenOn: given?.presentedAt, context: context
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
        // With no presentation on record, an undated one, as the cell's Mastered attaches:
        // the mark says she has it, not that she was given it today (bug hunt 2026-11-03 #8).
        let given = allLAs.first { !$0.isDeleted && $0.isPresented && $0.studentIDs.contains(studentIDString) }
            ?? addStudentToPresentedLesson(
                student: student, lesson: lesson,
                in: allLAs, attachment: .undated, context: context
            )

        if let studentID = student.id, let lessonID = lesson.id {
            ChecklistCellRecords.closeWorkForMastery(studentID: studentID, lessonID: lessonID, in: context)
        }

        upsertLessonPresentation(
            studentID: studentIDString, lessonID: lessonIDString,
            state: .proficient, from: prefetchedLPs, givenOn: given?.presentedAt, context: context
        )
    }
}
