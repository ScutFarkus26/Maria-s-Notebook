//
//  YearPlanSatisfaction.swift
//  Maria's Notebook
//
//  Which year-plan intentions the record already answers.
//
//  A year-plan entry is an intention: this child, this lesson, some day soon.
//  It stops being an intention the moment the lesson is actually given, and
//  the record of that is a `CDLessonPresentation` row — one per child per
//  presentation, written by `LifecycleService.recordPresentation`.
//
//  This is derived, not stored, for the same reason `isBehindPace` is: a
//  stored flag would have to be written by whichever device did the recording,
//  and `CDYearPlanEntry` lives in the *private* store while
//  `CDLessonPresentation` lives in the *shared* one. An assistant's recording
//  reaches the lead guide as a shared-zone history row and nothing else, so a
//  flag set at record time would close the entry only on the device that
//  happened to file it. Reading the shared row directly means the lead guide's
//  plan settles as soon as the assistant's presentation syncs in, on every
//  device at once, with nothing to migrate.
//
//  Satisfaction is a plain existence check — a presentation for this child and
//  this lesson, whenever it happened. It is deliberately not gated on the
//  entry's `createdAt`: a plan is routinely batch-added for a whole sequence
//  after the first lessons in it have already been given, and a date gate
//  would leave exactly those entries nagging forever.
//
//  This means an entry cannot express "give it again". In this app a
//  deliberate repeat is a `CDLessonAssignment` — schedule the lesson again,
//  and it appears on the calendar as its own presentation. Re-dating a
//  year-plan entry for a lesson already given will not bring it back into the
//  planned list; scheduling an assignment is the gesture that means "again".
//
//  Read once per load and passed down, never called per row: `isBehindPace` is
//  read inside `YearPlanCalendarItem`, which is evaluated per calendar cell per
//  render, and a per-entry fetch there would be a fetch storm inside `body`.
//

import CoreData
import Foundation

/// The (child, lesson) pairs that already have a presentation on record.
///
/// `nonisolated` so `CDYearPlanEntry` can read it: the Core Data model classes
/// and their extensions are nonisolated under the project's main-actor default,
/// and `isBehindPace` is one of theirs.
nonisolated struct YearPlanSatisfaction: Sendable {
    private struct Pair: Hashable {
        let studentID: String
        let lessonID: String
    }

    private let given: Set<Pair>

    /// Nothing on record. For call sites that have no context to read from, and
    /// for previews.
    static let none = YearPlanSatisfaction(given: [])

    // MARK: - Building

    /// One fetch for every child named, reduced to the pairs it proves.
    /// A dictionary fetch: only the two string columns are read, so a child
    /// with hundreds of presentations does not fault hundreds of objects.
    static func index(
        forStudents studentIDs: [String], in context: NSManagedObjectContext
    ) -> YearPlanSatisfaction {
        let wanted = Set(studentIDs.filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return .none }

        let entityName = CDFetchRequest(CDLessonPresentation.self).entityName ?? "LessonPresentation"
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["studentID", "lessonID"]
        request.returnsDistinctResults = true
        request.predicate = NSPredicate(format: "studentID IN %@", Array(wanted))

        let rows = (try? context.fetch(request)) ?? []
        var pairs: Set<Pair> = []
        pairs.reserveCapacity(rows.count)
        for row in rows {
            guard let studentID = row["studentID"] as? String, !studentID.isEmpty,
                  let lessonID = row["lessonID"] as? String, !lessonID.isEmpty
            else { continue }
            pairs.insert(Pair(studentID: studentID, lessonID: lessonID))
        }
        return YearPlanSatisfaction(given: pairs)
    }

    /// The index these entries need, scoped to the children they belong to.
    static func index(
        for entries: [CDYearPlanEntry], in context: NSManagedObjectContext
    ) -> YearPlanSatisfaction {
        index(forStudents: Array(Set(entries.map(\.studentID))), in: context)
    }

    // MARK: - Reading

    func isSatisfied(_ entry: CDYearPlanEntry) -> Bool {
        given.contains(Pair(studentID: entry.studentID, lessonID: entry.lessonID))
    }
}
