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

    @Test("The Restock card shows only when something is needed")
    func restockCardNeedsANeed() {
        #expect(TodaySectionVisibility.showsRestock(officeRun: 0, toOrder: 0) == false)
        #expect(TodaySectionVisibility.showsRestock(officeRun: 1, toOrder: 0))
        #expect(TodaySectionVisibility.showsRestock(officeRun: 0, toOrder: 2))
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

    @Test("The agenda, its meetings and Gone quiet are in the phone ordering and own the macOS left column")
    func agendaPlacement() {
        #expect(TodaySectionVisibility.phoneOrder.contains(.agenda))
        #expect(TodaySectionVisibility.macLeftColumnOrder == [.agenda, .meetings, .goneQuiet])
        #expect(TodaySectionVisibility.macRightColumnOrder.contains(.agenda) == false)
        #expect(TodaySectionVisibility.macRightColumnOrder.contains(.meetings) == false)
        #expect(TodaySectionVisibility.macRightColumnOrder.contains(.goneQuiet) == false)
    }

    @Test("Meetings follow the lessons directly on the phone")
    func meetingsFollowTheAgendaOnThePhone() throws {
        let order = TodaySectionVisibility.phoneOrder
        let agenda = try #require(order.firstIndex(of: .agenda))
        #expect(order[agenda + 1] == .meetings)
    }

    @Test("Gone quiet follows the meetings on the phone, then the Needs-a-lesson card and the todos")
    func goneQuietFollowsTheMeetingsOnThePhone() throws {
        let order = TodaySectionVisibility.phoneOrder
        let meetings = try #require(order.firstIndex(of: .meetings))
        #expect(order[meetings + 1] == .goneQuiet)
        #expect(order[meetings + 2] == .dayCards)
        #expect(order[meetings + 3] == .todos)
    }

    @Test("The phone leads with the plan: lessons (with the Next card), meetings, Gone quiet")
    func phoneLeadsWithThePlan() {
        #expect(Array(TodaySectionVisibility.phoneOrder.prefix(3)) == [.agenda, .meetings, .goneQuiet])
    }

    @Test("Gone quiet shows only when some open work has gone quiet")
    func goneQuietNeedsQuietWork() {
        #expect(TodaySectionVisibility.showsGoneQuiet(count: 0) == false)
        #expect(TodaySectionVisibility.showsGoneQuiet(count: 1))
    }

    @Test("The Meetings section shows only on a day with a scheduled meeting")
    func meetingsNeedAMeeting() {
        #expect(TodaySectionVisibility.showsMeetings(count: 0) == false)
        #expect(TodaySectionVisibility.showsMeetings(count: 1))
    }

    @Test("The macOS right column is the phone ordering minus the plan")
    func macRightColumnMirrorsThePhone() {
        #expect(
            TodaySectionVisibility.macRightColumnOrder
                == TodaySectionVisibility.phoneOrder.filter {
                    $0 != .agenda && $0 != .meetings && $0 != .goneQuiet
                }
        )
    }

    @Test("The macOS right column leads with the Needs-a-lesson card, then todos")
    func macRightColumnLeads() {
        #expect(Array(TodaySectionVisibility.macRightColumnOrder.prefix(2)) == [.dayCards, .todos])
        #expect(TodaySectionVisibility.macRightColumnOrder.last == .doneToday)
    }

    @Test("The Mac places every section, each in one column")
    func macPlacesEverySectionOnce() {
        let left = Set(TodaySectionVisibility.macLeftColumnOrder)
        let right = Set(TodaySectionVisibility.macRightColumnOrder)
        #expect(left.isDisjoint(with: right))
        #expect(left.union(right) == Set(TodaySection.allCases))
    }

    @Test("No ordering repeats a section")
    func orderingsAreDuplicateFree() {
        #expect(Set(TodaySectionVisibility.phoneOrder).count == TodaySectionVisibility.phoneOrder.count)
        #expect(
            Set(TodaySectionVisibility.macLeftColumnOrder).count
                == TodaySectionVisibility.macLeftColumnOrder.count
        )
        #expect(
            Set(TodaySectionVisibility.macRightColumnOrder).count
                == TodaySectionVisibility.macRightColumnOrder.count
        )
    }

    @Test("Every section the enum knows about is placed on the phone")
    func everySectionIsPlaced() {
        let placed = Set(TodaySectionVisibility.phoneOrder)
        #expect(placed == Set(TodaySection.allCases))
    }
}
