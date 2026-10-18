import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Bug hunt 2026-10-17 review (a1), #5: a child back after days away and
// marked Left Early still got "Welcome back". Leaving early isn't coming in.
// 2026-09-28 is a Monday.
@Suite("Assistant welcome back skips Left Early (Fix1017ReviewA1)")
@MainActor
struct AssistantWelcomeFix1017ReviewA1Tests {

    @Test("Marking a returning child Left Early welcomes no one")
    func leftEarlyNoWelcome() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        for iso in ["2026-09-23", "2026-09-24", "2026-09-25"] {
            let record = CDAttendanceRecord(context: context)
            record.studentID = maya.id?.uuidString ?? ""
            record.date = try AssistantTestSupport.day(iso)
            record.status = .absent
        }
        #expect(context.safeSave())

        let model = AssistantTestSupport.viewModel(stack, on: try AssistantTestSupport.day("2026-09-28"))
        let row = try #require(model.rows.first { $0.name == "Maya Stone" })
        #expect(row.daysAway == 3)

        model.setStatus(.leftEarly, for: row)
        #expect(model.rows.first { $0.name == "Maya Stone" }?.status == .leftEarly)
        #expect(model.welcome == nil)
    }
}
