//
//  NotebookJunkCleanup.swift
//  Cosmic Daybook
//
//  Settings › Troubleshooting › "Clean up leftovers": the one-time sweep of
//  records the notebook no longer reads, found by the 2026-09-30 store audit
//  (iPhone copy: about 3,340 of 12,257 synced records). Every one costs a
//  row plus CloudKit's ~3 KB cached copy on each device, and the same again
//  in iCloud.
//
//  What it removes, and why each is safe:
//  - Presentation records with no child and no lesson (Nov 2025 – Feb 2026):
//    nothing can show a record that names neither.
//  - Students on work that no longer exists: the spring-2026 participants
//    every backup round-trip brought back detached.
//  - Blank attendance rows: opening a day makes an unmarked row per child
//    (`CDAttendanceStore.ensureRecords`), and nothing marked them. Only
//    days before today, never a locked day, and only rows holding nothing.
//  - Empty unlinked copies of a reminder (same title, due date and
//    completion moment; no notes) that also exists linked to Apple Reminders
//    or with notes (or, with neither, every empty copy but the oldest). An
//    open reminder is never a copy of a completed one. `EventKitMirror` only
//    ever cleans up linked rows.
//  - Notes with no text, photo or tags that aren't pinned, flagged or in a report.
//  - Work steps with no work, sample-work steps with no sample work, and
//    completion records whose work is gone. Notes written on such a record
//    are kept: they're detached first (the relationship cascades), so they
//    stay in the child's notes, and the preview says how many.
//
//  And, by Danny's choice (2026-09-30):
//  - Planned year-plan entries of children who have left are skipped (not
//    deleted), as a departure does today (`StudentDeparturePlans.skip`).
//  - Documents with no file at all are removed.
//  - Presentation records of lessons that were deleted are removed.
//
//  Meeting work reviews of deleted work are kept on purpose
//  (`WorkDeletionService` leaves them as meeting history).
//
//  Until schema 23 it also tidied the track entities (steps with no track,
//  empty tracks, enrollments with no track); they left the private store
//  with `docs/Plans/Plan - Retire the track entities.md`.
//
//  `run(in:today:apply:within:)` counts with `apply: false` and changes with
//  `apply: true` through one code path, so the preview and the run can't
//  disagree; given the preview, the run touches only records the preview
//  named (and the backup made after it holds), never one that arrived from
//  iCloud since. It never saves.
//

import CoreData
import Foundation

nonisolated enum NotebookJunkCleanup {

    /// What a pass found, or changed.
    struct Counts: Equatable, Sendable {
        var blankPresentations = 0
        var detachedWorkParticipants = 0
        var blankAttendance = 0
        var duplicateReminders = 0
        var emptyNotes = 0
        var orphanWorkSteps = 0
        var orphanSampleWorkSteps = 0
        var completionRecordsOfDeletedWork = 0
        /// Notes on those completion records, kept (detached, not removed).
        var completionNotesKept = 0
        var presentationsOfDeletedLessons = 0
        var departedPlansSkipped = 0
        var documentsWithoutFile = 0

        /// The records the pass removes and the ones it changes, so the run that follows a
        /// preview is held to them.
        var removing: Set<NSManagedObjectID> = []
        var changing: Set<NSManagedObjectID> = []

        /// Records removed.
        var removed: Int {
            blankPresentations + detachedWorkParticipants + blankAttendance
                + duplicateReminders + emptyNotes + orphanWorkSteps + orphanSampleWorkSteps
                + completionRecordsOfDeletedWork + presentationsOfDeletedLessons + documentsWithoutFile
        }

        /// Records kept but changed.
        var changed: Int { departedPlansSkipped }

        var isEmpty: Bool { removed == 0 && changed == 0 }
    }

    /// Finds the junk and, with `apply`, removes or fixes it; given `preview`, only records
    /// it named. Runs on the context's queue; the caller saves.
    static func run(
        in context: NSManagedObjectContext, today: Date = Date(), apply: Bool, within preview: Counts? = nil
    ) -> Counts {
        var counts = Counts()
        var doomed: [NSManagedObject] = []
        func remove(_ objects: [NSManagedObject], into count: inout Int) {
            let kept = preview.map { preview in objects.filter { preview.removing.contains($0.objectID) } } ?? objects
            count = kept.count
            doomed += kept
        }
        func held<T>(_ changes: [T], _ object: (T) -> NSManagedObject) -> [T] {
            guard let preview else { return changes }
            return changes.filter { preview.changing.contains(object($0).objectID) }
        }

        let lessonIDs = idSet(CDLesson.self, in: context)
        let workIDs = idSet(CDWorkModel.self, in: context)

        remove(fetch(CDWorkParticipantEntity.self, "work == nil", in: context),
               into: &counts.detachedWorkParticipants)
        remove(fetch(CDWorkStep.self, "work == nil", in: context), into: &counts.orphanWorkSteps)
        remove(fetch(CDSampleWorkStep.self, "sampleWork == nil", in: context),
               into: &counts.orphanSampleWorkSteps)

        let presentations = fetch(CDLessonPresentation.self, nil, in: context)
        remove(presentations.filter { $0.studentID.trimmed().isEmpty && $0.lessonID.trimmed().isEmpty },
               into: &counts.blankPresentations)
        // A history row whose lesson was deleted is junk only when nothing keeps
        // it: deleting a lesson keeps the presentations already given (and their
        // rows) as history under the lesson's remembered title, and keeps a
        // mastery mark as a mark of its own (`LessonDeletion`, 2026-10-10 hunt).
        // What's left is a plain "given" row with no presentation behind it.
        let assignmentIDs = idSet(CDLessonAssignment.self, in: context)
        remove(presentations.filter { record in
            guard !record.lessonID.trimmed().isEmpty else { return false }
            guard !lessonIDs.contains(normalized(record.lessonID)) else { return false }
            if let presentationID = record.presentationID, !presentationID.trimmed().isEmpty,
               assignmentIDs.contains(normalized(presentationID)) {
                return false
            }
            if record.masteredAt != nil || record.state == .proficient { return false }
            return true
        }, into: &counts.presentationsOfDeletedLessons)

        remove(blankAttendance(in: context, today: today), into: &counts.blankAttendance)
        remove(duplicateReminders(in: context), into: &counts.duplicateReminders)
        remove(emptyNotes(in: context), into: &counts.emptyNotes)
        remove(fetch(CDWorkCompletionRecord.self, nil, in: context).filter {
            !workIDs.contains(normalized($0.workID))
        }, into: &counts.completionRecordsOfDeletedWork)
        remove(fetch(CDDocument.self, nil, in: context).filter {
            $0.pdfData == nil && $0.pdfFileBookmark == nil && $0.pdfFileRelativePath.trimmed().isEmpty
        }, into: &counts.documentsWithoutFile)

        let departedPlans = held(departedStudentPlans(in: context)) { $0 }
        counts.departedPlansSkipped = departedPlans.count
        counts.removing = Set(doomed.map(\.objectID))
        counts.changing = Set(departedPlans.map(\.objectID))
        counts.completionNotesKept = notesKept(on: doomed, removing: counts.removing).count

        guard apply else { return counts }
        carryOut(departedPlans: departedPlans, doomed: doomed, in: context)
        return counts
    }

    /// The run's changes and deletes, unsaved.
    private static func carryOut(
        departedPlans: [CDYearPlanEntry],
        doomed: [NSManagedObject],
        in context: NSManagedObjectContext
    ) {
        for entry in departedPlans where entry.isPlanned {
            entry.status = .skipped
        }
        // Every note on a doomed completion record, not only the ones the preview counted:
        // the delete cascades, and a note that arrived since must not go with it.
        for note in notesKept(on: doomed, removing: []) where !note.isDeleted {
            note.workCompletionRecord = nil
        }
        for object in doomed where !object.isDeleted {
            context.delete(object)
        }
    }

    /// Notes on the completion records in `doomed` that aren't themselves being removed
    /// (an empty note goes as an empty note). `WorkCompletionRecord.notes` cascades, so
    /// these are detached before the delete.
    private static func notesKept(on doomed: [NSManagedObject], removing: Set<NSManagedObjectID>) -> [CDNote] {
        doomed.compactMap { $0 as? CDWorkCompletionRecord }
            .flatMap { ($0.notes as? Set<CDNote>) ?? [] }
            .filter { !$0.isDeleted && !removing.contains($0.objectID) }
    }

    // MARK: - Buckets

    /// Unmarked rows holding nothing, on days before today that aren't locked.
    static func blankAttendance(in context: NSManagedObjectContext, today: Date) -> [CDAttendanceRecord] {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(
            format: "statusRaw == %@ AND date < %@",
            AttendanceStatus.unmarked.rawValue, AppCalendar.startOfDay(today) as NSDate
        )
        let lockedDays = Set(
            fetch(CDAttendanceDayLock.self, nil, in: context).compactMap { $0.date.map(AppCalendar.startOfDay) }
        )
        return context.safeFetch(request).filter { record in
            guard let date = record.date, !lockedDays.contains(AppCalendar.startOfDay(date)) else { return false }
            let reason = record.absenceReasonRaw
            return (reason.isEmpty || reason == AbsenceReason.none.rawValue)
                && (record.note ?? "").trimmed().isEmpty
                && record.markedAt == nil && record.leftAt == nil && record.leavesAt == nil
                && record.returnedAt == nil
        }
    }

    /// Empty unlinked copies of a reminder (same title, due date and
    /// completion): all of them when a linked copy or one with notes exists,
    /// otherwise all but the oldest. A copy with notes text or note items is
    /// never a copy, an open reminder never groups with a completed one, and
    /// completed ones group only when they were completed at the same moment
    /// (a weekly "Order paper" done on two days is two reminders, not copies).
    static func duplicateReminders(in context: NSManagedObjectContext) -> [CDReminder] {
        let reminders = fetch(CDReminder.self, nil, in: context)
        let groups = Dictionary(grouping: reminders) { reminder in
            let completion = reminder.isCompleted
                ? "done@\(reminder.completedAt?.timeIntervalSince1970 ?? -1)" : "open"
            return "\(reminder.title.folded())|\(reminder.dueDate?.timeIntervalSince1970 ?? -1)|\(completion)"
        }
        var doomed: [CDReminder] = []
        for group in groups.values where group.count > 1 {
            let empty = group.filter { reminder in
                reminder.eventKitReminderID == nil && (reminder.notes ?? "").trimmed().isEmpty
                    && (reminder.noteItems?.count ?? 0) == 0
            }
            if empty.count < group.count {
                doomed += empty
            } else {
                doomed += empty.sorted(by: olderFirst).dropFirst()
            }
        }
        return doomed
    }

    /// Notes with nothing in them and nothing set on them.
    static func emptyNotes(in context: NSManagedObjectContext) -> [CDNote] {
        fetch(CDNote.self, "isPinned == NO AND needsFollowUp == NO AND includeInReport == NO", in: context)
            .filter { note in
                note.body.trimmed().isEmpty && (note.imagePath ?? "").trimmed().isEmpty && note.tagsArray.isEmpty
            }
    }

    /// Still-planned year-plan entries of withdrawn or transferred children: the entries
    /// `StudentDeparturePlans.plannedEntries` finds when a child leaves, read here off the
    /// main actor.
    static func departedStudentPlans(in context: NSManagedObjectContext) -> [CDYearPlanEntry] {
        let departed = fetch(CDStudent.self, nil, in: context)
            .filter { $0.isWithdrawn || $0.isTransferred }
            .compactMap { $0.id?.uuidString }
        guard !departed.isEmpty else { return [] }
        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(
            format: "studentID IN %@ AND statusRaw == %@", departed, YearPlanEntryStatus.planned.rawValue
        )
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    // MARK: - Helpers

    private static func fetch<T: NSManagedObject>(
        _ type: T.Type, _ predicate: String?, in context: NSManagedObjectContext
    ) -> [T] {
        let request = CDFetchRequest(type)
        if let predicate { request.predicate = NSPredicate(format: predicate) }
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    /// Every row's `id`, normalized, for matching the string ids other rows carry.
    private static func idSet<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) -> Set<String> {
        Set(fetch(type, nil, in: context).compactMap { ($0.value(forKey: "id") as? UUID)?.uuidString })
    }

    /// An id string in `UUID.uuidString` form when it parses, else as written.
    private static func normalized(_ id: String) -> String {
        UUID(uuidString: id.trimmed())?.uuidString ?? id.trimmed()
    }

    private static func olderFirst(_ lhs: NSManagedObject, _ rhs: NSManagedObject) -> Bool {
        let lhsDate = lhs.value(forKey: "createdAt") as? Date ?? .distantFuture
        let rhsDate = rhs.value(forKey: "createdAt") as? Date ?? .distantFuture
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
    }
}
