import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The guide's lessons reach the Schedule tab for today and the 13 days after
// it only (`TimetableBookingWindow`, plan "Domain logic fixes", A14): outside
// those days the tab says why they're missing, rather than "Nothing".
@Suite("Assistant Schedule tab: the booking window")
@MainActor
struct AssistantScheduleWindowTests: AssistantScheduleFixture {

    let stack: CoreDataStack
    let monday: Date
    let morning: Date

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        monday = try AssistantTestSupport.day("2026-10-26")
        morning = try #require(AppCalendar.shared.date(byAdding: .minute, value: 9 * 60 + 15, to: monday))
    }

    private func day(_ offset: Int) throws -> Date {
        try #require(AppCalendar.shared.date(byAdding: .day, value: offset, to: monday))
    }

    @Test("Today through 13 days ahead say nothing; the days before and after say why lessons are missing")
    func outsideTheWindowSaysWhy() throws {
        _ = makeLanes()
        #expect(context.safeSave())
        let tab = model(guideName: "Danny")
        #expect(tab.bookingWindowLine == nil)
        tab.show(try day(13))
        #expect(tab.bookingWindowLine == nil)
        tab.show(try day(14))
        #expect(tab.bookingWindowLine == "Danny's lessons show for today and the next two weeks.")
        tab.show(try day(-1))
        #expect(tab.bookingWindowLine == "Danny's lessons show for today and the next two weeks.")
    }
}
