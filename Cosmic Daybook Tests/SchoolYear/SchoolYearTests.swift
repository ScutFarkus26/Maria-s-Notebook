import Foundation
import Testing
@testable import CosmicDaybook

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

    /// Runs `body` with every school-year default isolated, restoring whatever the machine
    /// had — a Mac test host shares the app's real defaults.
    private func withCounterDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let keys = [
            UserDefaultsKeys.schoolYearStartMonth, UserDefaultsKeys.schoolYearStartDay,
            UserDefaultsKeys.schoolYearSelection, UserDefaultsKeys.schoolYearCounterEpoch,
            UserDefaultsKeys.schoolYearCountersResetAtYearStart,
            UserDefaultsKeys.schoolYearCounterPromptAnsweredYear
        ]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) }
            YearPlanStaleness.invalidateCache()
        }
        body()
    }

    @Test("The epoch clamps older dates forward and leaves this year's alone")
    func counterClamping() {
        withCounterDefaults {
            let store = SchoolYearStore()
            store.startMonth = 9
            store.startDay = 1
            store.setCountersResetAtYearStart(true)
            let start = store.current.start
            let lastYear = cal.date(byAdding: .month, value: -4, to: start)!
            let thisYear = cal.date(byAdding: .day, value: 3, to: start)!
            #expect(SchoolYearCounters.isResetting)
            #expect(SchoolYearCounters.countFrom(lastYear) == start)
            #expect(SchoolYearCounters.countFrom(thisYear) == thisYear)
            #expect(SchoolYearCounters.countFrom(Date.distantPast) == start)
            #expect(SchoolYearCounters.countFrom(nil as Date?) == nil)

            store.setCountersResetAtYearStart(false)
            #expect(!SchoolYearCounters.isResetting)
            #expect(SchoolYearCounters.countFrom(lastYear) == lastYear) // untouched
        }
    }

    @Test("Turning the reset on follows the year start; off counts all history")
    func counterToggle() {
        withCounterDefaults {
            let store = SchoolYearStore()
            store.startMonth = 9
            store.startDay = 1

            store.setCountersResetAtYearStart(true)
            #expect(store.isResettingCounters)
            #expect(store.counterEpoch == store.current.start)
            #expect(SchoolYearCounters.epoch == store.current.start) // read off the main actor

            store.setCountersResetAtYearStart(false)
            #expect(!store.isResettingCounters)
            #expect(store.counterEpoch == nil)
            #expect(SchoolYearCounters.epoch == nil)
        }
    }

    @Test("Moving the start date moves the counters with it — no stored date to fall behind")
    func counterFollowsStartEdit() {
        withCounterDefaults {
            let store = SchoolYearStore()
            store.setCountersResetAtYearStart(true)
            store.startMonth = 9
            store.startDay = 1
            let septemberStart = store.current.start

            store.startMonth = 8
            store.startDay = 25
            #expect(store.current.start != septemberStart)
            #expect(store.counterEpoch == store.current.start)
            #expect(SchoolYearCounters.epoch == store.current.start)
        }
    }

    @Test("A legacy stored epoch — even last year's — reads as 'reset' and follows this year")
    func legacyEpochBecomesMode() {
        withCounterDefaults {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: UserDefaultsKeys.schoolYearCountersResetAtYearStart)
            defaults.set(
                day(2025, 9, 1).timeIntervalSinceReferenceDate, forKey: UserDefaultsKeys.schoolYearCounterEpoch
            )
            defaults.set(2025, forKey: UserDefaultsKeys.schoolYearCounterPromptAnsweredYear)

            let store = SchoolYearStore()
            #expect(store.isResettingCounters)
            #expect(store.counterEpoch == store.current.start)
            #expect(SchoolYearCounters.hasExplicitMode(in: defaults)) // written once, so it can sync
        }
    }

    @Test("A legacy install with no epoch keeps counting all history")
    func legacyNoEpochStaysAllHistory() {
        withCounterDefaults {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: UserDefaultsKeys.schoolYearCountersResetAtYearStart)
            defaults.removeObject(forKey: UserDefaultsKeys.schoolYearCounterEpoch)
            defaults.set(2025, forKey: UserDefaultsKeys.schoolYearCounterPromptAnsweredYear)

            let store = SchoolYearStore()
            #expect(!store.isResettingCounters)
            #expect(SchoolYearCounters.epoch == nil)
        }
    }

    @Test("A new school year offers to switch the lens once; answering either way stops it")
    func newYearPrompt() {
        withCounterDefaults {
            let store = SchoolYearStore()
            store.startMonth = 9
            store.startDay = 1
            let lastYear = SchoolYear.beginning(
                in: store.current.beginYear - 1, startMonth: 9, startDay: 1, calendar: cal
            )
            store.select(lastYear)
            UserDefaults.standard.set(
                store.current.beginYear - 1, forKey: UserDefaultsKeys.schoolYearCounterPromptAnsweredYear
            )

            let reopened = SchoolYearStore()
            #expect(reopened.needsNewYearPrompt)
            reopened.switchToNewYear()
            #expect(!reopened.needsNewYearPrompt)
            #expect(reopened.isCurrentYearSelected)

            reopened.select(lastYear)
            UserDefaults.standard.set(
                reopened.current.beginYear - 1, forKey: UserDefaultsKeys.schoolYearCounterPromptAnsweredYear
            )
            let declined = SchoolYearStore()
            #expect(declined.needsNewYearPrompt)
            declined.keepCurrentView()
            #expect(!declined.needsNewYearPrompt)
            #expect(!declined.isCurrentYearSelected)
        }
    }

    @Test("No new-year prompt while the lens already shows this year")
    func noPromptOnCurrentYear() {
        withCounterDefaults {
            let store = SchoolYearStore()
            store.selectCurrentYear()
            UserDefaults.standard.set(
                store.current.beginYear - 1, forKey: UserDefaultsKeys.schoolYearCounterPromptAnsweredYear
            )
            #expect(!SchoolYearStore().needsNewYearPrompt)
        }
    }

    // MARK: - Sync from the store's side

    @Test("An edit publishes all three settings; applying synced settings publishes nothing")
    func editsPublishSyncedDoNot() {
        withCounterDefaults {
            let store = SchoolYearStore()
            var sent: [[Int]] = []
            store.publish = { month, day, resetting in sent.append([month, day, resetting ? 1 : 0]) }

            store.startMonth = 8
            #expect(sent.last == [8, store.startDay, store.isResettingCounters ? 1 : 0])
            store.setCountersResetAtYearStart(false)
            #expect(sent.last == [8, store.startDay, 0])

            let count = sent.count
            let defaults = UserDefaults.standard
            defaults.set(7, forKey: UserDefaultsKeys.schoolYearStartMonth)
            defaults.set(15, forKey: UserDefaultsKeys.schoolYearStartDay)
            defaults.set(true, forKey: UserDefaultsKeys.schoolYearCountersResetAtYearStart)
            store.applySyncedSettings()
            #expect(store.startMonth == 7)
            #expect(store.startDay == 15)
            #expect(store.isResettingCounters)
            #expect(sent.count == count) // no echo back to iCloud
        }
    }

    @Test("A start edit re-resolves the viewing lens against the new boundary")
    func startEditRefreshesLens() {
        withCounterDefaults {
            let store = SchoolYearStore()
            store.publish = { _, _, _ in }
            store.startMonth = 9
            store.startDay = 1
            store.selectCurrentYear()
            store.startMonth = 8
            store.startDay = 25
            #expect(store.activeRange?.start == store.current.start)
        }
    }
}
