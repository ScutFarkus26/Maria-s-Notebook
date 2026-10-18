import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, school days and MCP replies (#10, #14, #16).
/// Serialized: every test resets the shared school calendar's cache.
@Suite("School days, MCP school calendar and orders (Fix1017 Cal)", .serialized)
@MainActor
struct SchoolDaysAndOrdersFix1017Cal {

    private struct Harness {
        let tools: [MCPToolDefinition]
        let context: NSManagedObjectContext
    }

    private func makeHarness() throws -> Harness {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let dependencies = AppDependencies(coreDataStack: stack)
        SchoolCalendarService.shared.invalidateCache()
        return Harness(
            tools: MCPNotebookTools.makeTools(context: { context }, dependencies: { dependencies }),
            context: context
        )
    }

    private func call(_ name: String, _ arguments: [String: JSONValue], in harness: Harness) async throws -> String {
        let tool = try #require(harness.tools.first { $0.name == name })
        return try await tool.handler(arguments)
    }

    private func outcome(of block: () async throws -> String) async throws -> (MCPCallOutcome, String) {
        let outcome = MCPCallOutcome()
        let reply = try await MCPCallOutcome.$current.withValue(outcome) { try await block() }
        return (outcome, reply)
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, hour: Int = 0) throws -> Date {
        try #require(AppCalendar.shared.date(
            from: DateComponents(year: year, month: month, day: dayOfMonth, hour: hour)
        ))
    }

    @discardableResult
    private func nonSchoolDay(
        on date: Date, reason: String? = nil, in context: NSManagedObjectContext
    ) -> CDNonSchoolDay {
        let row = CDNonSchoolDay(context: context)
        row.date = date
        row.reason = reason
        return row
    }

    private func count<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: CDFetchRequest(type))
    }

    // MARK: - #10 set_school_days matches the whole day

    /// A day off stored at 10:00 (another device, an import) is still that
    /// day: turning it back on removes it, where the exact-midnight match
    /// missed it and replied that the day was already in session.
    @Test("#10 A day off stored at another hour can be turned back on")
    func inSessionClearsDayStoredAtAnotherHour() throws {
        let harness = try makeHarness()
        let thursday = try day(2026, 11, 26)
        nonSchoolDay(on: try day(2026, 11, 26, hour: 10), reason: "Thanksgiving", in: harness.context)
        #expect(CoreDataTestHelpers.save(harness.context))

        let change = try SchoolCalendarService.shared.setSchoolDay(
            thursday, inSession: true, using: harness.context
        )
        #expect(change == .markedSchool)
        #expect(CoreDataTestHelpers.save(harness.context))
        #expect(try count(CDNonSchoolDay.self, in: harness.context) == 0)
    }

    @Test("#10 Marking a day off that is already off at another hour adds no second row")
    func noSchoolDoesNotDuplicateDayStoredAtAnotherHour() throws {
        let harness = try makeHarness()
        nonSchoolDay(on: try day(2026, 11, 26, hour: 10), in: harness.context)
        #expect(CoreDataTestHelpers.save(harness.context))

        let change = try SchoolCalendarService.shared.setSchoolDay(
            try day(2026, 11, 26), inSession: false, using: harness.context
        )
        #expect(change == .unchanged)
        #expect(try count(CDNonSchoolDay.self, in: harness.context) == 1)
    }

    @Test("#10 A weekend override stored at another hour counts as that day's")
    func weekendOverrideAtAnotherHour() throws {
        let harness = try makeHarness()
        let override = CDSchoolDayOverride(context: harness.context)
        override.date = try day(2026, 10, 10, hour: 9)
        #expect(CoreDataTestHelpers.save(harness.context))

        let again = try SchoolCalendarService.shared.setSchoolDay(
            try day(2026, 10, 10), inSession: true, using: harness.context
        )
        #expect(again == .unchanged)
        #expect(try count(CDSchoolDayOverride.self, in: harness.context) == 1)

        let off = try SchoolCalendarService.shared.setSchoolDay(
            try day(2026, 10, 10), inSession: false, using: harness.context
        )
        #expect(off == .markedNonSchool)
        #expect(try count(CDSchoolDayOverride.self, in: harness.context) == 0)
    }

    // MARK: - #14 school_calendar reads a day as a day

    /// Two devices marked Thanksgiving, one with the reason and one at 10:00;
    /// the Friday after was marked too. The read counts two days in one run
    /// with the reason, not three days in three runs.
    @Test("#14 A day marked twice counts once, and a break stays one run with its reason")
    func duplicateRowsCountOnce() async throws {
        let harness = try makeHarness()
        nonSchoolDay(on: try day(2026, 11, 26), in: harness.context)
        nonSchoolDay(on: try day(2026, 11, 26, hour: 10), reason: "Thanksgiving", in: harness.context)
        nonSchoolDay(on: try day(2026, 11, 27), reason: "Thanksgiving", in: harness.context)
        let saturday = CDSchoolDayOverride(context: harness.context)
        saturday.date = try day(2026, 11, 14)
        let sameSaturday = CDSchoolDayOverride(context: harness.context)
        sameSaturday.date = try day(2026, 11, 14, hour: 8)
        #expect(CoreDataTestHelpers.save(harness.context))

        let calendar = try await call("school_calendar", [
            "from": .string("2026-11-01"), "to": .string("2026-11-30")
        ], in: harness)
        #expect(calendar.contains("No-school weekdays from 2026-11-01 to 2026-11-30 (2):"))
        #expect(calendar.contains("- 2026-11-26 (Thursday) to 2026-11-27 (Friday), 2 weekdays — Thanksgiving"))
        #expect(calendar.contains("Weekends marked as school days (1):"))

        let single = try await call("school_calendar", ["date": .string("2026-11-26")], in: harness)
        #expect(single.contains("is a no-school day — Thanksgiving."))
    }

    // MARK: - #16 set_school_days on a weekend with a reason

    /// A weekend is out of school without a row, so the reason is stored
    /// nowhere: the reply says so instead of echoing it as saved.
    @Test("#16 A weekend with a reason says the reason isn't kept")
    func weekendReasonIsNotClaimed() async throws {
        let harness = try makeHarness()
        let reply = try await call("set_school_days", [
            "date": .string("2026-10-17"), "reason": .string("Fall break")
        ], in: harness)
        #expect(reply.contains("isn't kept"))
        #expect(!reply.contains("— Fall break"))
        #expect(try count(CDNonSchoolDay.self, in: harness.context) == 0)

        // A weekday in the same call keeps its reason.
        let mixed = try await call("set_school_days", [
            "dates": .array([.string("2026-10-16"), .string("2026-10-18")]),
            "reason": .string("Fall break")
        ], in: harness)
        #expect(mixed.contains("Marked 2026-10-16 no school — Fall break."))
        #expect(mixed.contains("isn't kept"))
        #expect(mixed.contains("2026-10-18"))
    }

    // MARK: - #16 update_order_items with nothing to change

    @Test("#16 update_order_items that changes nothing says so and isn't journaled")
    func orderUpdateWithNothingToChange() async throws {
        let harness = try makeHarness()
        _ = try await call("add_order_items", [
            "items": .array([.object(["url": .string("example.com/glue"), "title": .string("Glue sticks")])])
        ], in: harness)
        let item = try #require(harness.context.safeFetch(CDFetchRequest(CDOrderItem.self)).first)
        let id = try #require(item.id?.uuidString)
        let modifiedBefore = item.modifiedAt

        let (sameStage, stageReply) = try await outcome {
            try await call("update_order_items", [
                "items": .array([.object(["id": .string(id), "stage": .string("to_request")])])
            ], in: harness)
        }
        #expect(sameStage.wroteNothing)
        #expect(!stageReply.contains("Updated 1"))
        #expect(stageReply.contains("Nothing changed"))

        let (sameTitle, titleReply) = try await outcome {
            try await call("update_order_items", [
                "items": .array([.object([
                    "id": .string(id), "title": .string("Glue sticks"), "quantity": .int(Int(item.quantity))
                ])])
            ], in: harness)
        }
        #expect(sameTitle.wroteNothing)
        #expect(titleReply.contains("Nothing changed"))
        #expect(item.modifiedAt == modifiedBefore)

        let (renamed, renameReply) = try await outcome {
            try await call("update_order_items", [
                "items": .array([.object(["id": .string(id), "title": .string("Glue sticks, large")])])
            ], in: harness)
        }
        #expect(!renamed.wroteNothing)
        #expect(renameReply.contains("Updated 1"))
        #expect(item.title == "Glue sticks, large")
    }

    // #35's test moved to MCPOrdersAndDaysFix1017ReviewB (review (b)): it
    // moved the app's default zone, which the formatter, now made for
    // AppCalendar's zone, doesn't follow.
}
