import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// A target date from last April is last year's intention, not four months of
/// debt. `YearPlanStaleness` draws that line at the start of the school year
/// containing today, and `isBehindPace` refuses to call anything behind that
/// falls on the far side of it.
@Suite("Year Plan — Carried Over vs Behind Pace")
@MainActor
struct YearPlanStalenessTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    /// A fixed September start, so no test depends on the guide's settings or
    /// on the day it runs.
    private func yearStart(_ year: Int = 2026, month: Int = 9, day: Int = 1) -> Date {
        SchoolYear.boundaryDate(year: year, month: month, day: day, calendar: AppCalendar.shared)
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = dayOfMonth
        return AppCalendar.shared.date(from: comps) ?? Date()
    }

    @discardableResult
    private func seedEntry(
        in context: NSManagedObjectContext,
        plannedDate: Date?,
        status: YearPlanEntryStatus = .planned
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = UUID().uuidString
        entry.lessonID = UUID().uuidString
        entry.plannedDate = plannedDate
        entry.sequenceGroupKey = "Geometry::Polygons"
        entry.statusRaw = status.rawValue
        return entry
    }

    // MARK: - The rule

    @Test("a target before the year start is carried over; one on it or after is this year's")
    func boundaryIsTheYearStart() {
        let start = yearStart()
        let classify: (Date) -> YearPlanStaleness.Vintage = { date in
            YearPlanStaleness.classify(plannedDate: date, status: .planned, yearStart: start)
        }
        let april: YearPlanStaleness.Vintage = classify(day(2026, 4, 14))
        let lastAugustDay: YearPlanStaleness.Vintage = classify(day(2026, 8, 31))
        let onTheStart: YearPlanStaleness.Vintage = classify(start)
        let september: YearPlanStaleness.Vintage = classify(day(2026, 9, 15))
        let february: YearPlanStaleness.Vintage = classify(day(2027, 2, 3))
        #expect(april == .carriedOver)
        #expect(lastAugustDay == .carriedOver)
        // The start day itself belongs to this year.
        #expect(onTheStart == .current)
        #expect(september == .current)
        #expect(february == .current)
    }

    @Test("an undated entry is never carried over")
    func undatedEntriesAreCurrent() {
        let vintage = YearPlanStaleness.classify(
            plannedDate: nil, status: .planned, yearStart: yearStart()
        )
        #expect(vintage == .current)
    }

    @Test("promoted and skipped entries are never carried over, however old their target")
    func onlyPlannedEntriesCarryOver() {
        let start = yearStart()
        let old = day(2026, 4, 14)
        #expect(!YearPlanStaleness.isCarriedOver(plannedDate: old, status: .promoted, yearStart: start))
        #expect(!YearPlanStaleness.isCarriedOver(plannedDate: old, status: .skipped, yearStart: start))
        #expect(YearPlanStaleness.isCarriedOver(plannedDate: old, status: .planned, yearStart: start))
    }

    @Test("moving the school-year start moves the boundary with it")
    func nonDefaultYearStartMovesTheBoundary() {
        let august = yearStart(2026, month: 8, day: 15)
        let target = day(2026, 8, 20)
        // With an August 15 start, an August 20 target is this year's…
        #expect(!YearPlanStaleness.isCarriedOver(
            plannedDate: target, status: .planned, yearStart: august
        ))
        // …and with the default September 1 start, it is last year's.
        #expect(YearPlanStaleness.isCarriedOver(
            plannedDate: target, status: .planned, yearStart: yearStart()
        ))
    }

    // MARK: - The guard on isBehindPace

    @Test("a carried-over entry is never behind pace; one dated after the start still is")
    func behindPaceStopsAtTheYearStart() throws {
        let context = try makeContext()
        // Measured against the real boundary, since `isBehindPace` compares the
        // target against today as well as against the year start.
        let start = YearPlanStaleness.currentYearStart()
        let lastYear = AppCalendar.addingDays(-1, to: start)
        let thisYear = AppCalendar.addingDays(1, to: start)

        let carried = seedEntry(in: context, plannedDate: lastYear)
        let behind = seedEntry(in: context, plannedDate: thisYear)
        CoreDataTestHelpers.save(context)

        #expect(carried.isCarriedOver(yearStart: start))
        #expect(!carried.isBehindPace(satisfiedBy: .none, schoolYearStart: start))

        #expect(!behind.isCarriedOver(yearStart: start))
        // Only meaningful once the year is properly under way; on the first two
        // days of school nothing in it has had time to fall behind.
        if thisYear < AppCalendar.startOfDay(Date()) {
            #expect(behind.isBehindPace(satisfiedBy: .none, schoolYearStart: start))
        }
    }

    @Test("the calendar draws a carried-over entry as carried over, and still lets it be dragged")
    func calendarItemReadsCarriedOver() throws {
        let context = try makeContext()
        let start = YearPlanStaleness.currentYearStart()
        let entry = seedEntry(in: context, plannedDate: AppCalendar.addingDays(-10, to: start))
        CoreDataTestHelpers.save(context)

        let item = YearPlanCalendarItem(
            id: try #require(entry.id),
            lessonID: entry.lessonID,
            date: try #require(entry.plannedDate),
            kind: .planEntry(entry),
            satisfaction: .none,
            yearStart: start
        )
        #expect(item.displayStatus == .carriedOver)
        // Dragging one into this year is exactly the point.
        #expect(item.isEditable)
    }

    // MARK: - Labels

    @Test("the previous school year is the one the carried-over label names")
    func previousSchoolYearIsOneYearBack() {
        let current = YearPlanStaleness.schoolYear(containing: Date())
        let previous = YearPlanStaleness.previousSchoolYear()
        #expect(previous.beginYear == current.beginYear - 1)
        #expect(previous.end == current.start)
    }

    @Test("the memoized year start matches a freshly computed one")
    func cachedYearStartIsTheRealOne() {
        YearPlanStaleness.invalidateCache()
        let cold = YearPlanStaleness.currentYearStart()
        let warm = YearPlanStaleness.currentYearStart()
        let direct = SchoolYear.containing(
            Date(), startMonth: 9, startDay: 1, calendar: AppCalendar.shared
        ).start
        #expect(cold == warm)
        #expect(cold == direct)
    }
}
