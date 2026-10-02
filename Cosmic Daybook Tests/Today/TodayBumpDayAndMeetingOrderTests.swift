import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Where Today's moves and bumps land is named for the day they land on, and
/// the Meetings section keeps its own dragged order beside the agenda's.
@Suite("Today bump day and meeting order")
@MainActor
struct TodayBumpDayAndMeetingOrderTests {

    private let locale = Locale(identifier: "en_US_POSIX")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    /// Friday, October 2, 2026 at 10:00.
    private var friday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 10)) ?? Date()
    }

    private func day(after date: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) ?? date
    }

    // MARK: - Day names

    @Test("The next calendar day is \"tomorrow\"")
    func tomorrow() {
        let target = day(after: friday, 1)
        #expect(TodayBumpDay.name(for: target, today: friday, calendar: calendar, locale: locale) == "tomorrow")
        #expect(TodayBumpDay.title(for: target, today: friday, calendar: calendar, locale: locale) == "Tomorrow")
    }

    @Test("A school day later in the week is its weekday: Friday's next school day is Monday")
    func weekday() {
        let monday = day(after: friday, 3)
        #expect(TodayBumpDay.name(for: monday, today: friday, calendar: calendar, locale: locale) == "Monday")
        #expect(TodayBumpDay.title(for: monday, today: friday, calendar: calendar, locale: locale) == "Monday")
    }

    @Test("A school day a week or more away is a short date")
    func shortDate() {
        let afterBreak = day(after: friday, 10)
        #expect(TodayBumpDay.name(for: afterBreak, today: friday, calendar: calendar, locale: locale) == "Mon, Oct 12")
    }

    // MARK: - Meeting order

    private func meetings(_ count: Int, in context: NSManagedObjectContext) -> [CDScheduledMeeting] {
        (0..<count).map { _ in CDScheduledMeeting(context: context) }
    }

    @Test("Meetings come back in their saved order; one not yet ordered follows")
    func meetingOrderIsSaved() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let rows = meetings(3, in: context)
        let today = Date()
        TodayAgendaBuilder.saveMeetingOrder(
            meetingIDs: [rows[2], rows[0]].compactMap(\.id), day: today, context: context
        )

        let ordered = TodayAgendaBuilder.orderMeetings(rows, day: today, context: context)
        #expect(ordered.map(\.id) == [rows[2], rows[0], rows[1]].map(\.id))
    }

    @Test("Saving the lessons' order keeps the meetings' order, and the other way round")
    func ordersAreIndependent() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let rows = meetings(2, in: context)
        let today = Date()
        TodayAgendaBuilder.saveMeetingOrder(
            meetingIDs: [rows[1], rows[0]].compactMap(\.id), day: today, context: context
        )
        let lesson = CDLessonAssignment(context: context)
        lesson.id = UUID()
        TodayAgendaBuilder.saveOrder(items: [.lesson(lesson)], day: today, context: context)

        let ordered = TodayAgendaBuilder.orderMeetings(rows, day: today, context: context)
        #expect(ordered.map(\.id) == [rows[1], rows[0]].map(\.id))

        TodayAgendaBuilder.saveMeetingOrder(
            meetingIDs: [rows[0], rows[1]].compactMap(\.id), day: today, context: context
        )
        let saved = context.safeFetch(CDFetchRequest(CDTodayAgendaOrder.self))
        #expect(saved.filter { $0.itemType == .lesson }.map(\.itemID) == [lesson.id])
        #expect(saved.count(where: { $0.itemType == .meeting }) == 2)
    }
}
