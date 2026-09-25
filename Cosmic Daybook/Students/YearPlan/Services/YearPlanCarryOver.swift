//
//  YearPlanCarryOver.swift
//  Cosmic Daybook
//
//  What to do with last year's intentions.
//
//  `YearPlanStaleness` says which entries were planned for a school year that
//  has ended. This says what the guide can do about them, in bulk, per child:
//  leave them where they are, re-date them into this year, or skip them.
//
//  Re-dating is not "move them all to Monday". A sequence's shape is the plan —
//  three school days between these two, a fortnight before that one — and a
//  pile-up on the landing day would destroy exactly the intention the guide is
//  trying to keep. So the run is re-laid: the first entry lands on the first
//  open day at or after the landing date, and each one after it keeps the
//  number of *school* days that separated it from the entry before. Two targets
//  that shared a day still share one. Every result lands on an open day by
//  construction, so no `YearPlanPacing.resettle` pass is needed afterwards.
//
//  Shaped like `StudentDeparturePlans`: fetch → count → mutate, never save.
//  The caller saves once, so a sheet's whole run is one atomic write.
//

import CoreData
import Foundation

/// What the guide chose to do with one child's carried-over entries.
enum YearPlanCarryOverChoice: String, CaseIterable, Sendable {
    case leave
    case redate
    case skip

    var label: String {
        switch self {
        case .leave: return "Leave as is"
        case .redate: return "Re-date into this year"
        case .skip: return "Skip"
        }
    }
}

enum YearPlanCarryOver {

    /// One child's carried-over entries, counted for a chooser row.
    struct Survey: Equatable, Identifiable {
        let studentID: UUID
        let name: String
        let count: Int
        let earliest: Date?
        let latest: Date?

        var id: UUID { studentID }

        /// "7 carried over (Apr 14 – Jun 2)", or just the count when the run
        /// sits on a single day or has no dates to show.
        var detail: String {
            let noun = count == 1 ? "entry" : "entries"
            guard let earliest else { return "\(count) carried-over \(noun)" }
            let from = DateFormatters.mediumDate.string(from: earliest)
            guard let latest, AppCalendar.startOfDay(latest) != AppCalendar.startOfDay(earliest) else {
                return "\(count) carried over (\(from))"
            }
            return "\(count) carried over (\(from) – \(DateFormatters.mediumDate.string(from: latest)))"
        }
    }

    // MARK: - Reading

    /// One child's carried-over entries, in the order they were to be given.
    ///
    /// Promoted entries are left out: promotion means a real assignment on the
    /// calendar, and that assignment is the truth. An entry the presentation
    /// record already answers is left out too — nothing is owed for a lesson
    /// that has been given.
    static func entries(
        for studentID: UUID, in context: NSManagedObjectContext, yearStart: Date
    ) -> [CDYearPlanEntry] {
        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND statusRaw == %@",
            studentID.uuidString, YearPlanEntryStatus.planned.rawValue
        )
        let planned = context.safeFetch(request)
        guard !planned.isEmpty else { return [] }
        let satisfaction = YearPlanSatisfaction.index(for: planned, in: context)
        return planned
            .filter { !$0.isSatisfied(by: satisfaction) && $0.isCarriedOver(yearStart: yearStart) }
            .sorted(by: plannedOrder)
    }

    /// A row per child who has any, in roster order, skipping the children who
    /// have none — the chooser shows only the work there is.
    static func survey(
        _ students: [CDStudent], in context: NSManagedObjectContext, yearStart: Date
    ) -> [Survey] {
        students.compactMap { student in
            guard let studentID = student.id else { return nil }
            let found = entries(for: studentID, in: context, yearStart: yearStart)
            guard !found.isEmpty else { return nil }
            let dates = found.compactMap(\.plannedDate).sorted()
            return Survey(
                studentID: studentID,
                name: student.fullName,
                count: found.count,
                earliest: dates.first,
                latest: dates.last
            )
        }
    }

    // MARK: - Re-dating

    /// Re-lays `entries` from `landingOn`, keeping their order and the school
    /// days between them. Returns how many targets moved. Does not save.
    ///
    /// Pass one child's whole run, across all her sequences, so the shape of
    /// her year survives rather than each track landing on the same morning.
    @discardableResult
    static func redate(
        _ entries: [CDYearPlanEntry], landingOn: Date, in context: NSManagedObjectContext
    ) -> Int {
        let run = entries.filter { !$0.isDeleted && $0.plannedDate != nil }.sorted(by: plannedOrder)
        guard !run.isEmpty else { return 0 }

        var moved = 0
        var previousOld: Date?
        var previousNew = YearPlanPacing.schoolDay(onOrAfter: landingOn, in: context)

        for entry in run {
            guard let old = entry.plannedDate.map(AppCalendar.startOfDay) else { continue }
            var landing = previousNew
            if let previousOld {
                let gap = SchoolCalendarService.shared
                    .schoolDaysBetween(start: previousOld, end: old, using: context)
                if gap > 0 {
                    landing = YearPlanPacing.advance(
                        from: previousNew, bySchoolDays: Int64(gap), in: context
                    )
                }
            }
            if landing != old {
                entry.plannedDate = landing
                entry.modifiedAt = Date()
                moved += 1
            }
            previousOld = old
            previousNew = landing
        }
        return moved
    }

    /// How many of these targets now fall past the end of the school year.
    ///
    /// Re-dating a long run from late in the year can push its tail into next
    /// summer. That is reported rather than fixed: compressing the spacing to
    /// make it fit would silently rewrite the guide's pacing, and only she
    /// knows whether the answer is a earlier landing day or a shorter plan.
    static func landingAfterYearEnd(_ entries: [CDYearPlanEntry], yearEnd: Date) -> Int {
        entries.filter { entry in
            guard let date = entry.plannedDate else { return false }
            return AppCalendar.startOfDay(date) >= AppCalendar.startOfDay(yearEnd)
        }.count
    }

    /// Marks each entry skipped, through the same call the roster uses. Does
    /// not save, and never deletes.
    @discardableResult
    static func skip(_ entries: [CDYearPlanEntry]) -> Int {
        StudentDeparturePlans.skip(entries: entries)
    }

    // MARK: - Ordering

    /// Target date first, then the entry's own place in its sequence — the
    /// order the run was meant to be given in.
    private static func plannedOrder(_ lhs: CDYearPlanEntry, _ rhs: CDYearPlanEntry) -> Bool {
        let left = lhs.plannedDate ?? .distantFuture
        let right = rhs.plannedDate ?? .distantFuture
        if left != right { return left < right }
        return lhs.orderInSequence < rhs.orderInSequence
    }
}
