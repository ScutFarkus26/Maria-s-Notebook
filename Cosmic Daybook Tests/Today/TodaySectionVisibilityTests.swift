import Foundation
import Testing
@testable import CosmicDaybook

/// Boundary tests for `TodaySectionVisibility`, the rule that decides which
/// Today sections render at all.
///
/// Nothing here depends on the wall clock, the school calendar, or Core Data.
@Suite("Today section visibility")
struct TodaySectionVisibilityTests {

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

    // MARK: - Day pad

    @Test("The pad shows when it has writing on it, or when the guide opened it")
    func dayPadGate() {
        #expect(TodaySectionVisibility.showsDayPad(hasBody: false, isExpanded: false) == false)
        #expect(TodaySectionVisibility.showsDayPad(hasBody: false, isExpanded: true))
        #expect(TodaySectionVisibility.showsDayPad(hasBody: true, isExpanded: false))
        #expect(TodaySectionVisibility.showsDayPad(hasBody: true, isExpanded: true))
    }

    // MARK: - Orderings

    @Test("The agenda, its meetings, the schedules and Gone quiet own the macOS left column")
    func agendaPlacement() {
        #expect(TodaySectionVisibility.phoneOrder.contains(.agenda))
        #expect(TodaySectionVisibility.macLeftColumnOrder == [.agenda, .meetings, .schedule, .goneQuiet])
        #expect(TodaySectionVisibility.macRightColumnOrder.contains(.agenda) == false)
        #expect(TodaySectionVisibility.macRightColumnOrder.contains(.meetings) == false)
        #expect(TodaySectionVisibility.macRightColumnOrder.contains(.schedule) == false)
        #expect(TodaySectionVisibility.macRightColumnOrder.contains(.goneQuiet) == false)
    }

    @Test("Meetings follow the lessons directly on the phone")
    func meetingsFollowTheAgendaOnThePhone() throws {
        let order = TodaySectionVisibility.phoneOrder
        let agenda = try #require(order.firstIndex(of: .agenda))
        #expect(order[agenda + 1] == .meetings)
    }

    @Test("On the phone the meetings are followed by the schedules, Gone quiet, Needs-a-lesson and the todos")
    func goneQuietFollowsTheMeetingsOnThePhone() throws {
        let order = TodaySectionVisibility.phoneOrder
        let meetings = try #require(order.firstIndex(of: .meetings))
        #expect(order[meetings + 1] == .schedule)
        #expect(order[meetings + 2] == .goneQuiet)
        #expect(order[meetings + 3] == .dayCards)
        #expect(order[meetings + 4] == .todos)
    }

    @Test("The phone leads with the plan: lessons (with the Next card), meetings, schedules, Gone quiet")
    func phoneLeadsWithThePlan() {
        #expect(
            Array(TodaySectionVisibility.phoneOrder.prefix(4)) == [.agenda, .meetings, .schedule, .goneQuiet]
        )
    }

    @Test("The Schedule section shows only when the timetable has something on the day, and school is open")
    func scheduleNeedsARowOnASchoolDay() {
        #expect(TodaySectionVisibility.showsSchedule(rowCount: 0, isNonSchoolDay: false) == false)
        #expect(TodaySectionVisibility.showsSchedule(rowCount: 3, isNonSchoolDay: false))
        // A holiday Monday: the Monday blocks don’t happen.
        #expect(TodaySectionVisibility.showsSchedule(rowCount: 3, isNonSchoolDay: true) == false)
        #expect(TodaySectionVisibility.showsSchedule(rowCount: 0, isNonSchoolDay: true) == false)
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
                    $0 != .agenda && $0 != .meetings && $0 != .schedule && $0 != .goneQuiet
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
