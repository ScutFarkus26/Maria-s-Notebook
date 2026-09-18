import Foundation
import Testing
@testable import CosmicDaybook

/// Boundary tests for `TodaySectionVisibility`, the rule that decides which
/// Today sections render at all.
///
/// Every date case pins an explicit "now" against a pinned report cycle, so
/// nothing here depends on the wall clock, the school calendar, or Core Data.
@Suite("Today section visibility")
struct TodaySectionVisibilityTests {

    // MARK: - Fixtures

    private var calendar: Calendar { AppCalendar.shared }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        return AppCalendar.startOfDay(calendar.date(from: components)!)
    }

    /// The cycle for August 2026 reports: opens 1 September, due through the
    /// end of day 7 September.
    private var augustCycle: ReportMonth { ReportMonth(year: 2026, month: 8) }

    private var augustWindow: DateInterval { augustCycle.cycleWindow(calendar: calendar) }

    /// The whole enrolled roster in the live notebook.
    private let enrolledRoster = 22

    // MARK: - Count-gated sections

    @Test("Todos, calendar, observations and the retrospective need a row to show")
    func countGatedSectionsNeedARow() {
        #expect(TodaySectionVisibility.showsTodos(count: 0) == false)
        #expect(TodaySectionVisibility.showsTodos(count: 1))

        #expect(TodaySectionVisibility.showsCalendarEvents(count: 0) == false)
        #expect(TodaySectionVisibility.showsCalendarEvents(count: 1))

        #expect(TodaySectionVisibility.showsRecentNotes(count: 0) == false)
        #expect(TodaySectionVisibility.showsRecentNotes(count: 1))

        #expect(TodaySectionVisibility.showsDoneToday(total: 0) == false)
        #expect(TodaySectionVisibility.showsDoneToday(total: 1))
    }

    // MARK: - Reminders

    @Test("An empty reminder list hides the section entirely")
    func noRemindersHidesTheSection() {
        #expect(TodaySectionVisibility.showsReminders(overdue: 0, dueToday: 0, anytime: 0) == false)
        #expect(TodaySectionVisibility.showsAnytimeDisclosure(anytime: 0) == false)
    }

    @Test("Forty-one undated reminders show the section, but only as a collapsed disclosure")
    func undatedRemindersStayBehindTheDisclosure() {
        // The live notebook's standing pile: all undated, mostly last year's.
        #expect(TodaySectionVisibility.showsReminders(overdue: 0, dueToday: 0, anytime: 41))
        #expect(TodaySectionVisibility.showsAnytimeDisclosure(anytime: 41))
    }

    @Test("Overdue or due-today reminders show the section on the fold")
    func datedRemindersShowTheSection() {
        #expect(TodaySectionVisibility.showsReminders(overdue: 2, dueToday: 0, anytime: 0))
        #expect(TodaySectionVisibility.showsReminders(overdue: 0, dueToday: 3, anytime: 0))
        // Dated reminders alone offer no disclosure — there is nothing to hide.
        #expect(TodaySectionVisibility.showsAnytimeDisclosure(anytime: 0) == false)
    }

    // MARK: - Day pad

    @Test("The pad shows when it has writing on it, or when the guide opened it")
    func dayPadGate() {
        #expect(TodaySectionVisibility.showsDayPad(hasBody: false, isExpanded: false) == false)
        #expect(TodaySectionVisibility.showsDayPad(hasBody: false, isExpanded: true))
        #expect(TodaySectionVisibility.showsDayPad(hasBody: true, isExpanded: false))
        #expect(TodaySectionVisibility.showsDayPad(hasBody: true, isExpanded: true))
    }

    // MARK: - Parent reports

    @Test("The report nudge is silent before the cycle opens")
    func parentReportsBeforeTheCycleOpens() {
        #expect(TodaySectionVisibility.showsParentReports(
            now: day(2026, 8, 28),
            window: augustWindow,
            enrolled: enrolledRoster,
            sent: 0
        ) == false)
    }

    @Test("Inside the cycle window, nothing sent yet, the nudge is up")
    func parentReportsInsideTheWindow() {
        #expect(TodaySectionVisibility.showsParentReports(
            now: day(2026, 9, 3),
            window: augustWindow,
            enrolled: enrolledRoster,
            sent: 0
        ))
    }

    @Test("Past the end of the cycle window the nudge closes instead of nagging")
    func parentReportsAfterTheWindowCloses() {
        // This is the defect the gate fixes: day 10 with nothing sent used to
        // keep the banner up for the rest of the month.
        #expect(TodaySectionVisibility.showsParentReports(
            now: day(2026, 9, 10),
            window: augustWindow,
            enrolled: enrolledRoster,
            sent: 0
        ) == false)
    }

    @Test("Every report sent hides the nudge even mid-window")
    func parentReportsAllSent() {
        #expect(TodaySectionVisibility.showsParentReports(
            now: day(2026, 9, 3),
            window: augustWindow,
            enrolled: enrolledRoster,
            sent: enrolledRoster
        ) == false)
    }

    @Test("An empty roster has nothing to report on")
    func parentReportsNoStudents() {
        #expect(TodaySectionVisibility.showsParentReports(
            now: day(2026, 9, 3),
            window: augustWindow,
            enrolled: 0,
            sent: 0
        ) == false)
    }

    // MARK: - Orderings

    @Test("The agenda is in the phone ordering and owns the macOS right column")
    func agendaPlacement() {
        #expect(TodaySectionVisibility.phoneOrder.contains(.agenda))
        #expect(TodaySectionVisibility.macLeftColumnOrder.contains(.agenda) == false)
        #expect(TodaySectionVisibility.macRightColumnOrder == [.agenda])
    }

    @Test("The macOS left column is the phone ordering minus the agenda")
    func macLeftColumnMirrorsThePhone() {
        #expect(TodaySectionVisibility.macLeftColumnOrder == TodaySectionVisibility.phoneOrder.filter { $0 != .agenda })
    }

    @Test("Neither ordering repeats a section")
    func orderingsAreDuplicateFree() {
        #expect(Set(TodaySectionVisibility.phoneOrder).count == TodaySectionVisibility.phoneOrder.count)
        #expect(
            Set(TodaySectionVisibility.macLeftColumnOrder).count
                == TodaySectionVisibility.macLeftColumnOrder.count
        )
    }

    @Test("Every section the enum knows about is placed somewhere")
    func everySectionIsPlaced() {
        let placed = Set(TodaySectionVisibility.phoneOrder)
        #expect(placed == Set(TodaySection.allCases))
    }
}
