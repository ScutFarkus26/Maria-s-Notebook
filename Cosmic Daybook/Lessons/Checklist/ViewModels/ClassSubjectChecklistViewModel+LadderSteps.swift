// ClassAreaChecklistViewModel+LadderSteps.swift
// The cell card's ladder steps and the P key: each moves a child up to its rung and
// never down. Presented gives her the lesson today unless she already has it;
// Practicing and Reviewing also open (or move) her practice work. Planned is the
// Inbox toggle and Mastered is markComplete, both in +CellActions.

import Foundation
import CoreData
import OSLog

extension ClassAreaChecklistViewModel {

    /// Gives her the lesson today, unless she already has it on record.
    func markPresentedNoRecompute(student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext) {
        guard let studentUUID = student.id, let lessonUUID = lesson.id else { return }
        let studentIDString = studentUUID.uuidString
        let lessonIDString = lessonUUID.uuidString

        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        let allLAs = context.safeFetch(request)
        guard findGivenLessonContaining(student: studentIDString, in: allLAs) == nil else { return }

        addStudentToGivenLesson(
            student: student, studentIDString: studentIDString,
            lesson: lesson, in: allLAs, context: context
        )
        upsertLessonPresentation(
            studentID: studentIDString, lessonID: lessonIDString,
            state: .presented, context: context
        )
    }

    /// Practicing (`.active`) or Reviewing (`.review`): presented first if she isn't, then
    /// her open work on the lesson moved to `status`, or new work made for her.
    func markWorkNoRecompute(
        _ status: WorkStatus, student: CDStudent, lesson: CDLesson, context: NSManagedObjectContext
    ) {
        guard let studentUUID = student.id, let lessonUUID = lesson.id else { return }
        markPresentedNoRecompute(student: student, lesson: lesson, context: context)

        let open = openWork(of: studentUUID, onLesson: lessonUUID, context: context)

        do {
            if let open {
                guard open.status != status else { return }
                _ = try WorkLogService.log(
                    [.init(work: open, status: status)], context: context, saveImmediately: false
                )
                return
            }
            let work = try WorkRepository(context: context).createWork(
                studentID: studentUUID, lessonID: lessonUUID, saveImmediately: false
            )
            if status != work.status {
                _ = try WorkLogService.log(
                    [.init(work: work, status: status)], context: context, saveImmediately: false
                )
            }
        } catch {
            Self.logger.warning("Failed to set practice work for student \(studentUUID): \(error)")
        }
    }

    /// Her open work on the lesson, by the cell's own rule (`WorkVisibility`): the copy
    /// she owns first, then a shared row she is on. Group work is one linked copy per
    /// child, each naming the whole group, so the first open row naming her could be a
    /// classmate's, and moving it changed the classmate's work (bug hunt 2026-10-29 #10).
    /// Every row of the lesson is read, closed ones too: her closed copy is what says a
    /// classmate's open copy isn't hers.
    private func openWork(
        of studentID: UUID, onLesson lessonID: UUID, context: NSManagedObjectContext
    ) -> CDWorkModel? {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        request.relationshipKeyPathsForPrefetching = ["participants"]
        let rows = context.safeFetch(request).filter { !$0.isDeleted }
        let visibility = WorkVisibility(rows: rows)
        let open = rows.filter { $0.status.isOpen && visibility.isVisible($0, to: studentID) }
        return open.first { WorkGrouping.owner(of: $0) == studentID } ?? ClassGridEngine.cellWork(open)
    }
}
