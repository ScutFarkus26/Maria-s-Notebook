import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The grid shows the day's roll, not today's: a child who has since left shows
// on the days she was here, and a record that day always puts a child on it.
@Suite("Assistant roster by day")
@MainActor
struct AssistantRosterTests {

    @Test("A departed child shows through her last day and not after; a record keeps her on its day")
    func departedChild() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        let leah = AssistantTestSupport.student("Leah", "Hart", in: context)
        leah.enrollmentStatus = .transferred
        leah.dateWithdrawn = try AssistantTestSupport.day("2026-09-16")
        let late = AssistantTestSupport.student("Noa", "Winter", in: context)
        late.dateStarted = try AssistantTestSupport.day("2026-09-21")
        _ = context.safeSave()

        let model = AssistantTestSupport.viewModel(stack, on: try AssistantTestSupport.day("2026-09-16"))
        #expect(model.rows.map(\.student.firstName) == ["Ari", "Leah"])

        model.load(try AssistantTestSupport.day("2026-09-17"))
        #expect(model.rows.map(\.student.firstName) == ["Ari"])

        // Noa was typed in with a later start date, but a mark on the 17th
        // puts her on that day's roll.
        let record = CDAttendanceRecord(context: context)
        record.studentID = try #require(late.id?.uuidString)
        record.date = try AssistantTestSupport.day("2026-09-17")
        record.status = .present
        _ = context.safeSave()
        model.load()
        #expect(model.rows.map(\.student.firstName) == ["Ari", "Noa"])
    }
}
