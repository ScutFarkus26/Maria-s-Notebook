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
//  - Track steps with no track: the Jan–Mar 2026 steps cut off when the old
//    share zones split. Their tracks were rebuilt with new steps.
//  - Presentation records with no child and no lesson (Nov 2025 – Feb 2026):
//    nothing can show a record that names neither.
//  - Students on work that no longer exists: the spring-2026 participants
//    every backup round-trip brought back detached.
//  - Blank attendance rows: opening a day makes an unmarked row per child
//    (`CDAttendanceStore.ensureRecords`), and nothing marked them. Only
//    days before today, never a locked day, and only rows holding nothing.
//  - Empty unlinked copies of a reminder (same title, due date and
//    completion; no notes) that also exists linked to Apple Reminders or
//    with notes (or, with neither, every empty copy but the oldest). An open
//    reminder is never a copy of a completed one. `EventKitMirror` only ever
//    cleans up linked rows.
//  - Notes with no text, photo or tags that aren't pinned, flagged or in a report.
//  - Tracks with no steps that nothing points at.
//  - Work steps with no work, sample-work steps with no sample work, and
//    completion records whose work is gone.
//
//  And, by Danny's choice (2026-09-30):
//  - Planned year-plan entries of children who have left are skipped (not
//    deleted), as a departure does today (`StudentDeparturePlans.skip`).
//  - Enrollments with no track take the track their id or old
//    "Area|Sequence" key names; one whose child is already on that track, or
//    that names no track, is removed. An active one is never removed for an
//    inactive one, and one a note names (`studentTrackEnrollmentID`) stays.
//  - Documents with no file at all are removed.
//  - Presentation records of lessons that were deleted are removed.
//
//  Meeting work reviews of deleted work are kept on purpose
//  (`WorkDeletionService` leaves them as meeting history).
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
        var orphanTrackSteps = 0
        var blankPresentations = 0
        var detachedWorkParticipants = 0
        var blankAttendance = 0
        var duplicateReminders = 0
        var emptyNotes = 0
        var emptyTracks = 0
        var orphanWorkSteps = 0
        var orphanSampleWorkSteps = 0
        var completionRecordsOfDeletedWork = 0
        var presentationsOfDeletedLessons = 0
        var departedPlansSkipped = 0
        var enrollmentsRelinked = 0
        var enrollmentsRemoved = 0
        var documentsWithoutFile = 0

        /// The records the pass removes and the ones it changes, so the run that follows a
        /// preview is held to them.
        var removing: Set<NSManagedObjectID> = []
        var changing: Set<NSManagedObjectID> = []

        /// Records removed.
        var removed: Int {
            orphanTrackSteps + blankPresentations + detachedWorkParticipants + blankAttendance
                + duplicateReminders + emptyNotes + emptyTracks + orphanWorkSteps + orphanSampleWorkSteps
                + completionRecordsOfDeletedWork + presentationsOfDeletedLessons + enrollmentsRemoved
                + documentsWithoutFile
        }

        /// Records kept but changed.
        var changed: Int { departedPlansSkipped + enrollmentsRelinked }

        var isEmpty: Bool { removed == 0 && changed == 0 }

        /// One line per kind, in the guide's words, for the sheet and the log; kinds with
        /// nothing are left out.
        var lines: [String] {
            [
                Self.line(orphanTrackSteps, "track step with no track", "track steps with no track"),
                Self.line(
                    blankPresentations,
                    "lesson given with no child or lesson", "lessons given with no child or lesson"
                ),
                Self.line(
                    presentationsOfDeletedLessons,
                    "lesson given whose lesson was deleted", "lessons given whose lesson was deleted"
                ),
                Self.line(
                    detachedWorkParticipants,
                    "child on work that no longer exists", "children on work that no longer exists"
                ),
                Self.line(blankAttendance, "empty attendance entry", "empty attendance entries"),
                Self.line(
                    departedPlansSkipped,
                    "planned lesson for a child who's left, marked skipped",
                    "planned lessons for children who've left, marked skipped"
                ),
                Self.line(
                    enrollmentsRelinked,
                    "old track enrollment linked to its track", "old track enrollments linked to their tracks"
                ),
                Self.line(enrollmentsRemoved, "old track enrollment removed", "old track enrollments removed"),
                Self.line(duplicateReminders, "duplicate reminder", "duplicate reminders"),
                Self.line(emptyNotes, "empty note", "empty notes"),
                Self.line(documentsWithoutFile, "document with no file", "documents with no file"),
                Self.line(emptyTracks, "empty track", "empty tracks"),
                Self.line(orphanWorkSteps + orphanSampleWorkSteps, "work step with no work", "work steps with no work"),
                Self.line(
                    completionRecordsOfDeletedWork,
                    "completed-work entry for work that was deleted",
                    "completed-work entries for work that was deleted"
                )
            ]
            .compactMap { $0 }
        }

        /// "1 empty note", "3 empty notes", or nil for none.
        private static func line(_ count: Int, _ one: String, _ many: String) -> String? {
            guard count > 0 else { return nil }
            return "\(count.formatted()) \(count == 1 ? one : many)"
        }
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

        remove(fetch(CDTrackStep.self, "track == nil", in: context), into: &counts.orphanTrackSteps)
        remove(fetch(CDWorkParticipantEntity.self, "work == nil", in: context),
               into: &counts.detachedWorkParticipants)
        remove(fetch(CDWorkStep.self, "work == nil", in: context), into: &counts.orphanWorkSteps)
        remove(fetch(CDSampleWorkStep.self, "sampleWork == nil", in: context),
               into: &counts.orphanSampleWorkSteps)

        let presentations = fetch(CDLessonPresentation.self, nil, in: context)
        remove(presentations.filter { $0.studentID.trimmed().isEmpty && $0.lessonID.trimmed().isEmpty },
               into: &counts.blankPresentations)
        remove(presentations.filter { record in
            guard !record.lessonID.trimmed().isEmpty else { return false }
            return !lessonIDs.contains(normalized(record.lessonID))
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

        let enrollments = trackLessEnrollments(in: context)
        let relinks = held(enrollments.relinks) { $0.enrollment }
        counts.enrollmentsRelinked = relinks.count
        remove(enrollments.removals, into: &counts.enrollmentsRemoved)
        let relinkTargets = Set(enrollments.relinks.map(\.track.objectID))
        remove(emptyTracks(in: context).filter { !relinkTargets.contains($0.objectID) }, into: &counts.emptyTracks)

        let departedPlans = held(departedStudentPlans(in: context)) { $0 }
        counts.departedPlansSkipped = departedPlans.count
        counts.removing = Set(doomed.map(\.objectID))
        counts.changing = Set(relinks.map(\.enrollment.objectID) + departedPlans.map(\.objectID))

        guard apply else { return counts }
        carryOut(relinks: relinks, departedPlans: departedPlans, doomed: doomed, in: context)
        return counts
    }

    /// The run's changes and deletes, unsaved.
    private static func carryOut(
        relinks: [(enrollment: CDStudentTrackEnrollmentEntity, track: CDTrackEntity)],
        departedPlans: [CDYearPlanEntry],
        doomed: [NSManagedObject],
        in context: NSManagedObjectContext
    ) {
        for (enrollment, track) in relinks {
            enrollment.track = track
            if let id = track.id { enrollment.trackID = id.uuidString }
        }
        for entry in departedPlans where entry.isPlanned {
            entry.status = .skipped
        }
        for object in doomed where !object.isDeleted {
            context.delete(object)
        }
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
    /// never a copy, and an open reminder never groups with a completed one.
    static func duplicateReminders(in context: NSManagedObjectContext) -> [CDReminder] {
        let reminders = fetch(CDReminder.self, nil, in: context)
        let groups = Dictionary(grouping: reminders) { reminder in
            "\(reminder.title.folded())|\(reminder.dueDate?.timeIntervalSince1970 ?? -1)|\(reminder.isCompleted)"
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

    /// Tracks with no steps and no enrollments that no work or presentation names.
    static func emptyTracks(in context: NSManagedObjectContext) -> [CDTrackEntity] {
        var named = Set<String>()
        for work in fetch(CDWorkModel.self, "trackID != nil", in: context) {
            named.insert(normalized(work.trackID ?? ""))
        }
        for assignment in fetch(CDLessonAssignment.self, "trackID != nil", in: context) {
            named.insert(normalized(assignment.trackID ?? ""))
        }
        for enrollment in fetch(CDStudentTrackEnrollmentEntity.self, nil, in: context) {
            named.insert(normalized(enrollment.trackID))
        }
        return fetch(CDTrackEntity.self, nil, in: context).filter { track in
            (track.steps?.count ?? 0) == 0 && (track.enrollments?.count ?? 0) == 0
                && !named.contains(normalized(track.id?.uuidString ?? ""))
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

// MARK: - Enrollments

nonisolated extension NotebookJunkCleanup {

    /// Enrollments with no track: the ones to link to the track they name,
    /// and the ones to remove (the child is already on it, or no track matches).
    /// One a note names is never removed, nor an active one for an inactive one.
    static func trackLessEnrollments(
        in context: NSManagedObjectContext
    ) -> (relinks: [(enrollment: CDStudentTrackEnrollmentEntity, track: CDTrackEntity)],
          removals: [CDStudentTrackEnrollmentEntity]) {
        let tracks = fetch(CDTrackEntity.self, nil, in: context)
        let byID = Dictionary(tracks.compactMap { track in track.id.map { ($0.uuidString, track) } },
                              uniquingKeysWith: { first, _ in first })
        let byTitle = Dictionary(tracks.map { ($0.title.folded(), $0) }, uniquingKeysWith: { first, _ in first })
        let enrollments = fetch(CDStudentTrackEnrollmentEntity.self, nil, in: context)
        let noted = Set(fetch(CDNote.self, "studentTrackEnrollmentID != nil", in: context).compactMap {
            $0.studentTrackEnrollmentID.map(normalized)
        })
        // Child and track → whether the child is active on it.
        var onTrack: [String: Bool] = [:]
        for enrollment in enrollments {
            guard let track = enrollment.track else { continue }
            let key = "\(normalized(enrollment.studentID))|\(track.objectID.uriRepresentation())"
            onTrack[key] = onTrack[key] == true || enrollment.isActive
        }

        var relinks: [(enrollment: CDStudentTrackEnrollmentEntity, track: CDTrackEntity)] = []
        var removals: [CDStudentTrackEnrollmentEntity] = []
        let trackLess = enrollments.filter { $0.track == nil }
            .sorted { $0.isActive != $1.isActive ? $0.isActive : olderFirst($0, $1) }
        for enrollment in trackLess {
            let isNoted = noted.contains(enrollment.id?.uuidString ?? "")
            guard let track = byID[UUID(uuidString: enrollment.trackID)?.uuidString ?? ""]
                ?? legacyKeyTitle(enrollment.trackID).flatMap({ byTitle[$0.folded()] }) else {
                if !isNoted { removals.append(enrollment) }
                continue
            }
            let key = "\(normalized(enrollment.studentID))|\(track.objectID.uriRepresentation())"
            guard let activeOnTrack = onTrack[key] else {
                onTrack[key] = enrollment.isActive
                relinks.append((enrollment, track))
                continue
            }
            if !isNoted && (activeOnTrack || !enrollment.isActive) {
                removals.append(enrollment)
            }
        }
        return (relinks, removals)
    }

    /// The track title an old "Area|Sequence" key stood for, as
    /// `SequenceTrackService` writes titles; nil for anything else.
    static func legacyKeyTitle(_ key: String) -> String? {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return "\(String(parts[0]).trimmed()) — \(String(parts[1]).trimmed())"
    }
}
