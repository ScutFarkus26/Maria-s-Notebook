import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

/// Tests for the school-year "viewing lens": boundary math, the overlap/roster predicate
/// factories (exercised against a real in-memory store), and selection persistence tokens.
/// Serialized because the store tests touch the shared UserDefaults start-date keys.
@Suite("School Year", .serialized)
@MainActor
final class SchoolYearTests {

    private let cal = AppCalendar.shared

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        let date = AppCalendar.shared.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
        return AppCalendar.startOfDay(date)
    }

    // MARK: - Boundary math

    @Test("September start buckets dates into the right school year")
    func septemberBoundaries() {
        func begin(_ date: Date) -> Int {
            SchoolYear.containing(date, startMonth: 9, startDay: 1, calendar: cal).beginYear
        }
        #expect(begin(day(2025, 10, 1)) == 2025)   // fall → that year
        #expect(begin(day(2026, 2, 10)) == 2025)   // spring → still that year
        #expect(begin(day(2025, 9, 1)) == 2025)    // first day → inclusive
        #expect(begin(day(2025, 8, 31)) == 2024)   // day before → prior year
    }

    @Test("A configurable July start pulls summer into the new year")
    func configurableStart() {
        let september = SchoolYear.containing(day(2025, 8, 20), startMonth: 9, startDay: 1, calendar: cal)
        let july = SchoolYear.containing(day(2025, 8, 20), startMonth: 7, startDay: 1, calendar: cal)
        #expect(september.beginYear == 2024) // Aug 20 is before Sep 1
        #expect(july.beginYear == 2025)      // Aug 20 is after Jul 1
    }

    @Test("Invalid start day clamps to the last valid day of the month")
    func invalidDayClamps() {
        let february = SchoolYear.beginning(in: 2025, startMonth: 2, startDay: 31, calendar: cal)
        #expect(february.start == day(2025, 2, 28)) // 2025 is not a leap year
    }

    @Test("Labels and keys read correctly")
    func labelsAndKeys() {
        let year = SchoolYear.beginning(in: 2025, startMonth: 9, startDay: 1, calendar: cal)
        #expect(year.key == "2025-2026")
        #expect(year.label == "2025–2026")
    }

    // MARK: - Store

    @Test("Current year always contains today")
    func currentContainsToday() {
        let store = SchoolYearStore()
        store.startMonth = 9
        store.startDay = 1
        #expect(store.current.range.contains(AppCalendar.startOfDay(Date())))
    }

    @Test("Cycle lens spans three school years ending at the anchor")
    func cycleRange() {
        let store = SchoolYearStore()
        store.startMonth = 9
        store.startDay = 1
        let anchor = SchoolYear.beginning(in: 2025, startMonth: 9, startDay: 1, calendar: cal)
        let range = store.range(for: .cycle(anchor: anchor))
        #expect(range?.start == day(2023, 9, 1))
        #expect(range?.end == day(2026, 9, 1))
    }

    @Test("All-time lens applies no date range")
    func allTimeRange() {
        let store = SchoolYearStore()
        #expect(store.range(for: .allTime) == nil)
    }

    // MARK: - Persistence tokens

    @Test("Selection tokens round-trip")
    func tokenRoundTrip() {
        let year = SchoolYear.beginning(in: 2025, startMonth: 9, startDay: 1, calendar: cal)
        #expect(SchoolYearStore.token(for: .year(year)) == "year:2025")
        #expect(SchoolYearStore.token(for: .cycle(anchor: year)) == "cycle:2025")
        #expect(SchoolYearStore.token(for: .allTime) == "all")

        let restored = SchoolYearStore.selection(from: "year:2025", startMonth: 9, startDay: 1, calendar: cal)
        #expect(restored == .year(year))
        let restoredCycle = SchoolYearStore.selection(from: "cycle:2025", startMonth: 9, startDay: 1, calendar: cal)
        #expect(restoredCycle == .cycle(anchor: year))
        #expect(SchoolYearStore.selection(from: "all", startMonth: 9, startDay: 1, calendar: cal) == .allTime)
        #expect(SchoolYearStore.selection(from: "garbage", startMonth: 9, startDay: 1, calendar: cal) == nil)
    }

    // MARK: - Counter epoch

    /// Runs `body` with the counter defaults isolated, restoring whatever the machine had.
    private func withCounterDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let epochKey = UserDefaultsKeys.schoolYearCounterEpoch
        let answeredKey = UserDefaultsKeys.schoolYearCounterPromptAnsweredYear
        let savedEpoch = defaults.object(forKey: epochKey)
        let savedAnswered = defaults.object(forKey: answeredKey)
        defer {
            defaults.set(savedEpoch, forKey: epochKey)
            defaults.set(savedAnswered, forKey: answeredKey)
        }
        body()
    }

    @Test("The epoch clamps older dates forward and leaves this year's alone")
    func counterClamping() {
        withCounterDefaults {
            SchoolYearCounters.setEpoch(day(2026, 9, 1))
            #expect(SchoolYearCounters.isResetting)
            #expect(SchoolYearCounters.countFrom(day(2026, 5, 12)) == day(2026, 9, 1)) // last year
            #expect(SchoolYearCounters.countFrom(day(2026, 10, 3)) == day(2026, 10, 3)) // this year
            #expect(SchoolYearCounters.countFrom(Date.distantPast) == day(2026, 9, 1))
            #expect(SchoolYearCounters.countFrom(nil as Date?) == nil)

            SchoolYearCounters.setEpoch(nil)
            #expect(!SchoolYearCounters.isResetting)
            #expect(SchoolYearCounters.countFrom(day(2026, 5, 12)) == day(2026, 5, 12)) // untouched
        }
    }

    @Test("Turning the reset on pins the epoch to the year start; off counts all history")
    func counterToggle() {
        withCounterDefaults {
            let store = SchoolYearStore()
            store.startMonth = 9
            store.startDay = 1

            store.setCountersResetAtYearStart(true)
            #expect(store.isResettingCounters)
            #expect(store.counterEpoch == store.current.start)
            #expect(SchoolYearCounters.epoch == store.current.start) // mirrored for the engines

            store.setCountersResetAtYearStart(false)
            #expect(!store.isResettingCounters)
            #expect(SchoolYearCounters.epoch == nil)
        }
    }

    @Test("A new school year prompts once, and starting fresh moves the epoch and the lens")
    func counterResetPrompt() {
        withCounterDefaults {
            let store = SchoolYearStore()
            store.startMonth = 9
            store.startDay = 1

            // Pretend the last answer was for the previous school year.
            UserDefaults.standard.set(
                store.current.beginYear - 1, forKey: UserDefaultsKeys.schoolYearCounterPromptAnsweredYear
            )
            let reopened = SchoolYearStore()
            #expect(reopened.needsCounterResetPrompt)

            reopened.startFreshCounters()
            #expect(!reopened.needsCounterResetPrompt)
            #expect(reopened.counterEpoch == reopened.current.start)
            #expect(reopened.isCurrentYearSelected)
        }
    }

    @Test("Declining the prompt leaves counters alone and doesn't ask again this year")
    func counterResetDeclined() {
        withCounterDefaults {
            let store = SchoolYearStore()
            store.startMonth = 9
            store.startDay = 1
            store.setCountersResetAtYearStart(false)

            UserDefaults.standard.set(
                store.current.beginYear - 1, forKey: UserDefaultsKeys.schoolYearCounterPromptAnsweredYear
            )
            let reopened = SchoolYearStore()
            #expect(reopened.needsCounterResetPrompt)

            reopened.keepCountersRunning()
            #expect(!reopened.needsCounterResetPrompt)
            #expect(reopened.counterEpoch == nil)
        }
    }

    // MARK: - Predicate factories (against a real in-memory store)

    @Test("Point-in-time predicate keeps in-range and undated, drops out-of-range")
    func pointInTimePredicate() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let range = DateRange(start: day(2025, 9, 1), end: day(2026, 9, 1))

        let inRange = CDNote(context: ctx); inRange.id = UUID(); inRange.createdAt = day(2025, 10, 1)
        let outRange = CDNote(context: ctx); outRange.id = UUID(); outRange.createdAt = day(2025, 8, 1)
        let undated = CDNote(context: ctx); undated.id = UUID(); undated.createdAt = nil
        #expect(CoreDataTestHelpers.save(ctx))

        let request = NSFetchRequest<CDNote>(entityName: "Note")
        request.predicate = SchoolYearFilter.pointInTime("createdAt", in: range)
        let ids = Set(try ctx.fetch(request).compactMap(\.id))

        #expect(ids.contains(inRange.id!))
        #expect(!ids.contains(outRange.id!))
        #expect(ids.contains(undated.id!)) // fail-open
    }

    @Test("Span predicate shows open work that overlaps a later year")
    func spanPredicate() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let range = DateRange(start: day(2026, 9, 1), end: day(2027, 9, 1)) // 2026–2027

        // Started last year, still open, touched this year → shows.
        let spanning = CDWorkModel(context: ctx); spanning.id = UUID()
        spanning.createdAt = day(2026, 5, 1); spanning.completedAt = nil; spanning.lastTouchedAt = day(2026, 10, 1)
        // Completed before the range → hidden.
        let doneEarly = CDWorkModel(context: ctx); doneEarly.id = UUID()
        doneEarly.createdAt = day(2026, 5, 1); doneEarly.completedAt = day(2026, 6, 1); doneEarly.lastTouchedAt = day(2026, 6, 1)
        // Open, never touched, created in range → shows.
        let openInRange = CDWorkModel(context: ctx); openInRange.id = UUID()
        openInRange.createdAt = day(2026, 10, 1); openInRange.completedAt = nil; openInRange.lastTouchedAt = nil
        #expect(CoreDataTestHelpers.save(ctx))

        let request = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        request.predicate = SchoolYearFilter.span(
            createdAt: "createdAt", completedAt: "completedAt", touchedAt: "lastTouchedAt", in: range
        )
        let ids = Set(try ctx.fetch(request).compactMap(\.id))

        #expect(ids.contains(spanning.id!))
        #expect(ids.contains(openInRange.id!))
        #expect(!ids.contains(doneEarly.id!))
    }

    @Test("Roster predicate keeps students active during the range")
    func rosterPredicate() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let range = DateRange(start: day(2025, 9, 1), end: day(2026, 9, 1))

        let active = CDStudent(context: ctx); active.id = UUID()
        active.dateStarted = day(2024, 9, 1); active.dateWithdrawn = nil
        let withdrawnEarly = CDStudent(context: ctx); withdrawnEarly.id = UUID()
        withdrawnEarly.dateStarted = day(2023, 9, 1); withdrawnEarly.dateWithdrawn = day(2024, 6, 1)
        let joinedMid = CDStudent(context: ctx); joinedMid.id = UUID()
        joinedMid.dateStarted = day(2025, 10, 1); joinedMid.dateWithdrawn = nil
        let future = CDStudent(context: ctx); future.id = UUID()
        future.dateStarted = day(2026, 10, 1); future.dateWithdrawn = nil
        let undated = CDStudent(context: ctx); undated.id = UUID()
        undated.dateStarted = nil; undated.dateWithdrawn = nil
        #expect(CoreDataTestHelpers.save(ctx))

        let request = NSFetchRequest<CDStudent>(entityName: "Student")
        request.predicate = SchoolYearFilter.roster(in: range)
        let ids = Set(try ctx.fetch(request).compactMap(\.id))

        #expect(ids.contains(active.id!))
        #expect(ids.contains(joinedMid.id!))
        #expect(ids.contains(undated.id!)) // fail-open
        #expect(!ids.contains(withdrawnEarly.id!))
        #expect(!ids.contains(future.id!))
    }
}
