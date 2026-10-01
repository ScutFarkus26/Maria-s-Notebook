import CoreData
import Foundation

// The roster's table caches, and the change flags that decide when they rebuild.
//
// The table caches (days since last lesson, next-lesson names, latest
// observation dates) read lessons, presented assignments, notes and note
// links; an attendance tap moves none of those, so it reloads attendance
// alone unless one of them changed too. Both are watched with
// `ManagedObjectChangeFlag`, which sees every edit — the count tokens they
// replaced missed edits that left a count unchanged (a scheduled lesson
// marked presented, a renamed lesson).

extension StudentsViewModel {

    /// The day, and the counter epoch the school-day counts clamp to.
    struct TableCacheStamp: Equatable {
        let day: Date
        let epoch: Date?

        init(calendar: Calendar) {
            day = calendar.startOfDay(for: Date())
            epoch = SchoolYearCounters.epoch
        }
    }

    /// What `computeDaysSinceLastLessonCache` and `buildTableCaches` read:
    /// the students (their next lessons), lessons, presented assignments,
    /// notes and their links, and the school calendar the day count uses.
    nonisolated static let tableCacheInputEntities: Set<String> = [
        "Student", "Lesson", "LessonAssignment", "Note", "NoteStudentLink",
        "NonSchoolDay", "SchoolDayOverride"
    ]

    /// Everything a roster signal is read from: the table-cache inputs plus attendance.
    nonisolated static let signalInputEntities: Set<String> = tableCacheInputEntities.union(["AttendanceRecord"])

    // MARK: - Change flags

    func attendanceFlag(for context: NSManagedObjectContext) -> ManagedObjectChangeFlag {
        if let existing = attendanceInputs, existing.watches(context) { return existing }
        let flag = ManagedObjectChangeFlag(entityNames: ["AttendanceRecord"], context: context)
        attendanceInputs = flag
        return flag
    }

    func tableCacheFlag(for context: NSManagedObjectContext) -> ManagedObjectChangeFlag {
        if let existing = tableCacheInputs, existing.watches(context) { return existing }
        let flag = ManagedObjectChangeFlag(entityNames: Self.tableCacheInputEntities, context: context)
        tableCacheInputs = flag
        return flag
    }

    // MARK: - Next lessons

    /// The lessons some student lists as next, fetched by id — the only
    /// lessons the next-lesson names look up.
    static func nextLessons(for students: [CDStudent], in context: NSManagedObjectContext) -> [CDLesson] {
        let ids = Set(students.flatMap(\.nextLessonUUIDs))
        guard !ids.isEmpty else { return [] }
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id IN %@", Array(ids))
        return context.safeFetch(request)
    }

    // MARK: - Latest observations

    /// Each student's latest observation: a note indexed to her
    /// (`searchIndexStudentID`) or linked to her through a scoped (not
    /// whole-class) note, dated `updatedAt ?? createdAt`.
    ///
    /// Reads three columns per row as dictionaries when the context has no
    /// unsaved changes (a dictionary fetch cannot see them); the object path
    /// otherwise, so the answer is the same either way.
    static func latestObservationDates(
        for studentIDs: Set<UUID>, in context: NSManagedObjectContext
    ) -> [UUID: Date] {
        var latest: [UUID: Date] = [:]
        func note(_ studentID: UUID?, _ date: Date?) {
            guard let studentID, studentIDs.contains(studentID), let date else { return }
            latest[studentID] = max(latest[studentID] ?? .distantPast, date)
        }

        if !context.hasChanges,
           let noteRows = directNoteRows(in: context),
           let linkRows = linkRows(in: context) {
            for row in noteRows {
                note(row["student"] as? UUID, (row["updatedAt"] as? Date) ?? (row["createdAt"] as? Date))
            }
            for row in linkRows {
                note(
                    (row["student"] as? String).flatMap(UUID.init(uuidString:)),
                    (row["updatedAt"] as? Date) ?? (row["createdAt"] as? Date)
                )
            }
            return latest
        }

        let noteRequest = CDFetchRequest(CDNote.self)
        noteRequest.predicate = NSPredicate(format: "searchIndexStudentID != nil")
        for row in context.safeFetch(noteRequest) {
            note(row.searchIndexStudentID, row.updatedAt ?? row.createdAt)
        }
        let linkRequest: NSFetchRequest<CDNoteStudentLink> = NSFetchRequest(entityName: "NoteStudentLink")
        linkRequest.relationshipKeyPathsForPrefetching = ["note"]
        for link in context.safeFetch(linkRequest) {
            guard let linked = link.note, !linked.scopeIsAll else { continue }
            note(link.studentIDUUID, linked.updatedAt ?? linked.createdAt)
        }
        return latest
    }

    private static func column(
        _ keyPath: String, as name: String, type: NSAttributeType
    ) -> NSExpressionDescription {
        let description = NSExpressionDescription()
        description.name = name
        description.expression = NSExpression(forKeyPath: keyPath)
        description.expressionResultType = type
        return description
    }

    static func directNoteRows(in context: NSManagedObjectContext) -> [NSDictionary]? {
        let request = NSFetchRequest<NSDictionary>(entityName: "Note")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "searchIndexStudentID != nil")
        request.propertiesToFetch = [
            column("searchIndexStudentID", as: "student", type: .UUIDAttributeType),
            column("updatedAt", as: "updatedAt", type: .dateAttributeType),
            column("createdAt", as: "createdAt", type: .dateAttributeType)
        ]
        return try? context.fetch(request)
    }

    static func linkRows(in context: NSManagedObjectContext) -> [NSDictionary]? {
        let request = NSFetchRequest<NSDictionary>(entityName: "NoteStudentLink")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "note != nil AND note.scopeIsAll == NO")
        request.propertiesToFetch = [
            column("studentID", as: "student", type: .stringAttributeType),
            column("note.updatedAt", as: "updatedAt", type: .dateAttributeType),
            column("note.createdAt", as: "createdAt", type: .dateAttributeType)
        ]
        return try? context.fetch(request)
    }
}

// MARK: - Days since last lesson
// Reads the presented assignments of the last year once — as five columns, not
// as objects — and folds them into one date per student. Today's "need a
// lesson" count uses it too.

extension StudentsViewModel {

    /// One presented assignment reduced to the three facts the day count needs.
    private struct PresentedAssignment {
        let lessonID: UUID?
        let studentIDs: [UUID]
        let when: Date
    }

    /// The presented assignments of the last year, minus the ones for Parsha lessons.
    ///
    /// Both queries are shaped to read as little as the answer needs. The lesson
    /// query asks the store for the Parsha rows instead of folding every lesson
    /// name in Swift; the assignment query filters on `stateRaw` in SQL and reads
    /// dictionaries rather than faulting a year of objects — the old object path
    /// also read `resolvedLessonID` per row, which is a separate `SELECT` each.
    private struct LessonQueryContext {
        let presentedAssignments: [PresentedAssignment]

        init(viewContext: NSManagedObjectContext, calendar: Calendar) {
            // PERFORMANCE: Limit query to recent lessons (1 year) to avoid loading entire history
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date())
                ?? Date().addingTimeInterval(-365 * 24 * 3600)

            let excluded = Self.parshaLessonIDs(in: viewContext)
            // A row whose `lessonID` doesn't parse used to compare against a fresh
            // UUID, which is never in the excluded set — so it was kept. Keep it.
            presentedAssignments = Self.presentedRows(since: oneYearAgo, in: viewContext)
                .filter { row in
                    guard let lessonID = row.lessonID else { return true }
                    return !excluded.contains(lessonID)
                }
        }

        /// IDs of the lessons the day count ignores.
        ///
        /// `normalizedForComparison()` is trim + lowercase, which no predicate can
        /// express, so the store narrows to the rows that could possibly match and
        /// Swift makes the same decision it always did on that handful. `[c]` only —
        /// the fold is case-insensitive but *not* diacritic-insensitive.
        private static func parshaLessonIDs(in context: NSManagedObjectContext) -> Set<UUID> {
            let request = CDFetchRequest(CDLesson.self)
            request.predicate = NSPredicate(
                format: "area CONTAINS[c] %@ OR sequence CONTAINS[c] %@", "parsha", "parsha"
            )
            let candidates = context.safeFetch(request).filter {
                $0.area.normalizedForComparison() == "parsha"
                    || $0.sequence.normalizedForComparison() == "parsha"
            }
            return Set(candidates.compactMap(\.id))
        }

        private static func presentedRows(
            since cutoff: Date,
            in context: NSManagedObjectContext
        ) -> [PresentedAssignment] {
            let predicate = NSPredicate(
                format: "createdAt >= %@ AND stateRaw == %@",
                cutoff as CVarArg, LessonAssignmentState.presented.rawValue
            )
            // A dictionary-result fetch can't see unsaved inserts, so a dirty
            // context still takes the object path — the answer has to be identical.
            if !context.hasChanges, let rows = dictionaryRows(matching: predicate, in: context) {
                return rows
            }
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = predicate
            request.returnsObjectsAsFaults = false
            request.fetchBatchSize = 200
            return context.safeFetch(request).map {
                PresentedAssignment(
                    lessonID: $0.lessonIDUUID,
                    studentIDs: $0.resolvedStudentIDs,
                    when: $0.presentedAt ?? $0.scheduledFor ?? $0.createdAt ?? Date()
                )
            }
        }

        /// `nil` when the fetch fails, so the caller falls back to the object path.
        private static func dictionaryRows(
            matching predicate: NSPredicate,
            in context: NSManagedObjectContext
        ) -> [PresentedAssignment]? {
            let request = NSFetchRequest<NSDictionary>(entityName: "LessonAssignment")
            request.resultType = .dictionaryResultType
            request.predicate = predicate
            request.propertiesToFetch = [
                "presentedAt", "scheduledFor", "createdAt", "lessonID", "_studentIDsData"
            ]
            guard let rows = try? context.fetch(request) else { return nil }
            return rows.map { row in
                let when = (row["presentedAt"] as? Date)
                    ?? (row["scheduledFor"] as? Date)
                    ?? (row["createdAt"] as? Date)
                    ?? Date()
                // Same decoding the `studentIDs` accessor does, straight off the blob.
                let ids = CloudKitStringArrayStorage.decode(from: row["_studentIDsData"] as? Data)
                return PresentedAssignment(
                    lessonID: (row["lessonID"] as? String).flatMap { UUID(uuidString: $0) },
                    studentIDs: ids.compactMap { UUID(uuidString: $0) },
                    when: when
                )
            }
        }
    }

    func computeDaysSinceLastLessonCache(
        for students: [CDStudent],
        using viewContext: NSManagedObjectContext,
        calendar: Calendar
    ) -> [UUID: Int] {
        // Build shared query context once
        let context = LessonQueryContext(viewContext: viewContext, calendar: calendar)

        // Build a map of student ID to most recent lesson date
        var lastDateByStudent: [UUID: Date] = [:]
        for assignment in context.presentedAssignments {
            let when = assignment.when
            for sid in assignment.studentIDs {
                // Update if this is the first date or a more recent date
                if let existing = lastDateByStudent[sid] {
                    if when > existing {
                        lastDateByStudent[sid] = when
                    }
                } else {
                    lastDateByStudent[sid] = when
                }
            }
        }

        // Compute days since last lesson for each student
        var result: [UUID: Int] = [:]
        for student in students {
            guard let studentID = student.id else { continue }
            if let lastDate = lastDateByStudent[studentID] {
                // Use LessonAgeHelper to compute school days since last lesson
                result[studentID] = LessonAgeHelper.schoolDaysSinceCreation(
                    createdAt: lastDate,
                    asOf: Date(),
                    using: viewContext
                )
            } else {
                // No lesson found - return -1 to indicate no lesson
                result[studentID] = -1
            }
        }

        return result
    }
}
