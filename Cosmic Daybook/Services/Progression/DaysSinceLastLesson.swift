//
//  DaysSinceLastLesson.swift
//  Cosmic Daybook
//
//  "Days since last lesson", computed once (Simplify the app, Phase 3,
//  2026-10-18). Four screens each had a copy: the roster's lesson age and the
//  record's "School Days Since Last Lesson" (one shared rule since the
//  2026-10-17 bug hunt), the Presentations waits, and the lesson planner's
//  evidence. They agreed on little:
//  - Parsha lessons: the roster and Presentations left them out (area or
//    sequence "Parsha", trimmed, any case); the planner counted them.
//  - An undated "given earlier" mark: Presentations ignored it; the roster
//    dated it by when it was marked (`createdAt`), so a new child's August
//    catch-up read as "taught today"; the planner ignored it.
//  - The count: school days everywhere but the planner, which counted
//    calendar days.
//  One rule now: a given presentation, dated by when it was given
//  (`presentedAt`, else `scheduledFor`; undated marks say nothing about when),
//  Parsha lessons aside, counted in school days from the school-year epoch
//  (`SchoolCalendarService.schoolDaysSinceCreation`).
//

import CoreData
import Foundation

enum DaysSinceLastLesson {

    /// One given presentation, reduced to what the count reads.
    nonisolated struct Given: Sendable {
        let lessonID: UUID?
        let studentIDs: [UUID]
        /// When it was given; nil for an undated mark, which is skipped.
        let date: Date?
    }

    /// A child's last given lesson.
    nonisolated struct LastLesson: Sendable, Equatable {
        let date: Date
        let lessonID: UUID?
    }

    // MARK: - The Rule

    /// Parsha lessons never reset the count: area or sequence "Parsha",
    /// trimmed, in any case.
    nonisolated static func isParsha(area: String, sequence: String) -> Bool {
        area.normalizedForComparison() == "parsha" || sequence.normalizedForComparison() == "parsha"
    }

    /// When a presentation counts as given: its presentation date, else its
    /// scheduled date. Nil for an undated "given earlier" mark.
    nonisolated static func givenDate(presentedAt: Date?, scheduledFor: Date?) -> Date? {
        presentedAt ?? scheduledFor
    }

    /// Each child's last given lesson among `given`, Parsha lessons aside. A
    /// row whose lesson id doesn't parse is kept (it can't be a Parsha lesson
    /// anyone could name).
    nonisolated static func lastLessons(from given: [Given], parshaLessonIDs: Set<UUID>) -> [UUID: LastLesson] {
        var last: [UUID: LastLesson] = [:]
        for row in given {
            guard let date = row.date else { continue }
            if let lessonID = row.lessonID, parshaLessonIDs.contains(lessonID) { continue }
            for studentID in row.studentIDs where (last[studentID]?.date ?? .distantPast) < date {
                last[studentID] = LastLesson(date: date, lessonID: row.lessonID)
            }
        }
        return last
    }

    /// School days from `date` to `now`, from the school-year counter epoch on.
    static func schoolDays(since date: Date, asOf now: Date = Date(), using context: NSManagedObjectContext) -> Int {
        LessonAgeHelper.schoolDaysSinceCreation(createdAt: date, asOf: now, using: context)
    }

    // MARK: - From the Store

    /// Each child's last given lesson of the last year, from the store.
    ///
    /// Both queries read as little as the answer needs: the lesson query asks
    /// the store for the Parsha candidates instead of folding every lesson in
    /// Swift, and the assignment query filters in SQL and reads five columns
    /// as dictionaries rather than faulting a year of objects (a dirty context
    /// takes the object path, since a dictionary fetch can't see unsaved rows).
    static func lastLessons(
        in context: NSManagedObjectContext, now: Date = Date(), calendar: Calendar = AppCalendar.shared
    ) -> [UUID: LastLesson] {
        // A year back: the roster's window, so it never reads the whole history.
        let cutoff = calendar.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 24 * 3600)
        return lastLessons(
            from: presentedRows(since: cutoff, in: context), parshaLessonIDs: parshaLessonIDs(in: context)
        )
    }

    /// Presented assignments given since `cutoff`: windowed on the date the
    /// lesson was given, or on `createdAt` for a row without one. Windowing on
    /// `createdAt` alone dropped a lesson drafted over a year ago and given
    /// this week (bug hunt 2026-10-17 review, St #44).
    nonisolated static func presentedInWindowPredicate(since cutoff: Date) -> NSPredicate {
        NSPredicate(
            format: "stateRaw == %@ AND (presentedAt >= %@ OR (presentedAt == nil AND createdAt >= %@))",
            LessonAssignmentState.presented.rawValue, cutoff as CVarArg, cutoff as CVarArg
        )
    }

    /// IDs of the Parsha lessons. The store narrows to the rows that could
    /// match (`[c]` only: the fold is case-insensitive, not
    /// diacritic-insensitive) and `isParsha` decides on that handful.
    static func parshaLessonIDs(in context: NSManagedObjectContext) -> Set<UUID> {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(
            format: "area CONTAINS[c] %@ OR sequence CONTAINS[c] %@", "parsha", "parsha"
        )
        let parsha = context.safeFetch(request).filter { isParsha(area: $0.area, sequence: $0.sequence) }
        return Set(parsha.compactMap(\.id))
    }

    private static func presentedRows(since cutoff: Date, in context: NSManagedObjectContext) -> [Given] {
        let predicate = presentedInWindowPredicate(since: cutoff)
        if !context.hasChanges, let rows = dictionaryRows(matching: predicate, in: context) {
            return rows
        }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = predicate
        request.returnsObjectsAsFaults = false
        request.fetchBatchSize = 200
        return context.safeFetch(request).map {
            Given(
                lessonID: $0.lessonIDUUID,
                studentIDs: $0.resolvedStudentIDs,
                date: givenDate(presentedAt: $0.presentedAt, scheduledFor: $0.scheduledFor)
            )
        }
    }

    /// `nil` when the fetch fails, so the caller falls back to the object path.
    private static func dictionaryRows(
        matching predicate: NSPredicate, in context: NSManagedObjectContext
    ) -> [Given]? {
        let request = NSFetchRequest<NSDictionary>(entityName: "LessonAssignment")
        request.resultType = .dictionaryResultType
        request.predicate = predicate
        request.propertiesToFetch = ["presentedAt", "scheduledFor", "lessonID", "_studentIDsData"]
        guard let rows = try? context.fetch(request) else { return nil }
        return rows.map { row in
            // Same decoding the `studentIDs` accessor does, straight off the blob.
            let ids = CloudKitStringArrayStorage.decode(from: row["_studentIDsData"] as? Data)
            return Given(
                lessonID: (row["lessonID"] as? String).flatMap { UUID(uuidString: $0) },
                studentIDs: ids.compactMap { UUID(uuidString: $0) },
                date: givenDate(presentedAt: row["presentedAt"] as? Date, scheduledFor: row["scheduledFor"] as? Date)
            )
        }
    }
}
