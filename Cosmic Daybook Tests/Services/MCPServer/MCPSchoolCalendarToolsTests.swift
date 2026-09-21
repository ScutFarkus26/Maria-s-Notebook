import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP School Calendar Tools", .serialized)
@MainActor
struct MCPSchoolCalendarToolsTests {
    private struct Harness {
        let tools: [MCPToolDefinition]
        let context: NSManagedObjectContext
        let dependencies: AppDependencies
    }

    private func makeHarness() throws -> Harness {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let dependencies = AppDependencies(coreDataStack: stack)
        let tools = MCPNotebookTools.makeTools(context: { context }, dependencies: { dependencies })
        return Harness(tools: tools, context: context, dependencies: dependencies)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text)).startOfDay
    }

    private func nonSchoolDays(in context: NSManagedObjectContext) -> [CDNonSchoolDay] {
        context.safeFetch(CDFetchRequest(CDNonSchoolDay.self))
    }

    private func overrides(in context: NSManagedObjectContext) -> [CDSchoolDayOverride] {
        context.safeFetch(CDFetchRequest(CDSchoolDayOverride.self))
    }

    // MARK: - Registration

    @Test("the three calendar tools are registered with the right annotations")
    func toolsAreRegistered() throws {
        let harness = try makeHarness()
        let read = try tool(named: "school_calendar", in: harness.tools)
        #expect(read.annotations.readOnlyHint)
        let set = try tool(named: "set_school_days", in: harness.tools)
        #expect(!set.annotations.readOnlyHint && set.annotations.idempotentHint)
        let settings = try tool(named: "update_school_calendar", in: harness.tools)
        #expect(!settings.annotations.readOnlyHint && settings.annotations.idempotentHint)
    }

    // MARK: - set_school_days

    @Test("a weekday marked no school gets a NonSchoolDay with its reason, and the calendar shows it")
    func markWeekdayNoSchool() async throws {
        let harness = try makeHarness()
        let receipt = try await tool(named: "set_school_days", in: harness.tools).handler([
            "date": .string("2026-11-26"),
            "reason": .string("Thanksgiving")
        ])
        #expect(receipt.contains("Marked 2026-11-26 no school — Thanksgiving."))

        let rows = nonSchoolDays(in: harness.context)
        #expect(rows.count == 1)
        #expect(rows.first?.reason == "Thanksgiving")
        #expect(SchoolCalendarService.shared.isNonSchoolDaySync(try day("2026-11-26"), using: harness.context))

        let calendar = try await tool(named: "school_calendar", in: harness.tools).handler([
            "from": .string("2026-11-01"), "to": .string("2026-11-30")
        ])
        #expect(calendar.contains("No-school weekdays from 2026-11-01 to 2026-11-30 (1):"))
        #expect(calendar.contains("- 2026-11-26 (Thursday) — Thanksgiving"))

        let single = try await tool(named: "school_calendar", in: harness.tools).handler([
            "date": .string("2026-11-26")
        ])
        #expect(single.contains("is a no-school day — Thanksgiving."))
    }

    @Test("calling twice leaves one row and says the day was already set")
    func markingIsIdempotent() async throws {
        let harness = try makeHarness()
        let set = try tool(named: "set_school_days", in: harness.tools)
        _ = try await set.handler(["date": .string("2026-11-26")])
        let again = try await set.handler(["date": .string("2026-11-26")])
        #expect(again.contains("Already no school: 2026-11-26."))
        #expect(nonSchoolDays(in: harness.context).count == 1)

        let reasoned = try await set.handler([
            "date": .string("2026-11-26"), "reason": .string("Thanksgiving")
        ])
        #expect(reasoned.contains("Updated the reason on 2026-11-26"))
        #expect(nonSchoolDays(in: harness.context).first?.reason == "Thanksgiving")
    }

    @Test("a range skips weekends unless asked, and collapses into one line on the calendar")
    func rangeSkipsWeekends() async throws {
        let harness = try makeHarness()
        // 2026-12-21 is a Monday; 2027-01-01 a Friday: ten weekdays, one weekend inside.
        let receipt = try await tool(named: "set_school_days", in: harness.tools).handler([
            "from": .string("2026-12-21"), "to": .string("2027-01-01"),
            "reason": .string("Winter break")
        ])
        #expect(receipt.contains("Marked 10 days from 2026-12-21 to 2027-01-01 no school — Winter break."))
        #expect(nonSchoolDays(in: harness.context).count == 10)
        #expect(overrides(in: harness.context).isEmpty)

        let calendar = try await tool(named: "school_calendar", in: harness.tools).handler([
            "from": .string("2026-12-01"), "to": .string("2027-01-31")
        ])
        #expect(calendar.contains("- 2026-12-21 (Monday) to 2027-01-01 (Friday), 10 weekdays — Winter break"))
    }

    @Test("a range across a year is refused and from without to is refused")
    func rangeGuards() async throws {
        let harness = try makeHarness()
        let set = try tool(named: "set_school_days", in: harness.tools)
        await #expect(throws: MCPToolError.self) {
            _ = try await set.handler(["from": .string("2026-01-01"), "to": .string("2027-06-01")])
        }
        await #expect(throws: MCPToolError.self) {
            _ = try await set.handler(["from": .string("2026-01-01")])
        }
        await #expect(throws: MCPToolError.self) {
            _ = try await set.handler([:])
        }
        #expect(nonSchoolDays(in: harness.context).isEmpty)
    }

    @Test("a weekend set in session gets an override, and setting it back removes it")
    func weekendInSession() async throws {
        let harness = try makeHarness()
        let set = try tool(named: "set_school_days", in: harness.tools)
        let saturday = try day("2026-10-10")
        let receipt = try await set.handler(["date": .string("2026-10-10"), "in_session": .bool(true)])
        #expect(receipt.contains("Marked 2026-10-10 in session."))
        #expect(overrides(in: harness.context).count == 1)
        #expect(!SchoolCalendarService.shared.isNonSchoolDaySync(saturday, using: harness.context))

        let calendar = try await tool(named: "school_calendar", in: harness.tools).handler([
            "from": .string("2026-10-01"), "to": .string("2026-10-31")
        ])
        #expect(calendar.contains("Weekends marked as school days (1):"))
        #expect(calendar.contains("- 2026-10-10 (Saturday)"))

        let back = try await set.handler(["date": .string("2026-10-10")])
        #expect(back.contains("Marked 2026-10-10 no school."))
        #expect(overrides(in: harness.context).isEmpty)
        #expect(SchoolCalendarService.shared.isNonSchoolDaySync(saturday, using: harness.context))
    }

    @Test("a weekday set back in session loses its NonSchoolDay row")
    func weekdayBackInSession() async throws {
        let harness = try makeHarness()
        let set = try tool(named: "set_school_days", in: harness.tools)
        _ = try await set.handler(["dates": .array([.string("2026-11-25"), .string("2026-11-26")])])
        #expect(nonSchoolDays(in: harness.context).count == 2)

        let receipt = try await set.handler([
            "date": .string("2026-11-25"), "in_session": .bool(true)
        ])
        #expect(receipt.contains("Marked 2026-11-25 in session."))
        #expect(nonSchoolDays(in: harness.context).count == 1)
        #expect(!SchoolCalendarService.shared.isNonSchoolDaySync(try day("2026-11-25"), using: harness.context))
    }

    @Test("a reason alongside in_session is refused")
    func reasonWithInSessionRefused() async throws {
        let harness = try makeHarness()
        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "set_school_days", in: harness.tools).handler([
                "date": .string("2026-11-25"), "in_session": .bool(true), "reason": .string("x")
            ])
        }
    }

    // MARK: - update_school_calendar

    @Test("update_school_calendar changes the start and reports the resulting year")
    func updateStart() async throws {
        let harness = try makeHarness()
        let store = harness.dependencies.schoolYearStore
        let originalMonth = store.startMonth
        let originalDay = store.startDay
        let originalReset = store.isResettingCounters
        defer {
            store.startMonth = originalMonth
            store.startDay = originalDay
            store.setCountersResetAtYearStart(originalReset)
        }

        let receipt = try await tool(named: "update_school_calendar", in: harness.tools).handler([
            "start_month": .int(8), "start_day": .int(15)
        ])
        #expect(receipt.contains("Updated start month, start day."))
        #expect(receipt.contains("School year starts August 15."))
        #expect(store.startMonth == 8 && store.startDay == 15)

        let same = try await tool(named: "update_school_calendar", in: harness.tools).handler([
            "start_month": .int(8), "start_day": .int(15)
        ])
        #expect(same.contains("already had those settings"))

        let counters = try await tool(named: "update_school_calendar", in: harness.tools).handler([
            "counters_reset_at_year_start": .bool(false)
        ])
        #expect(counters.contains("Day counters run over all history."))
        #expect(!store.isResettingCounters)

        let read = try await tool(named: "school_calendar", in: harness.tools).handler([:])
        #expect(read.contains("School year starts August 15."))
        #expect(read.contains("Day counters run over all history."))
    }

    @Test("update_school_calendar refuses bad values and empty calls")
    func updateGuards() async throws {
        let harness = try makeHarness()
        let update = try tool(named: "update_school_calendar", in: harness.tools)
        await #expect(throws: MCPToolError.self) { _ = try await update.handler([:]) }
        await #expect(throws: MCPToolError.self) { _ = try await update.handler(["start_month": .int(13)]) }
        await #expect(throws: MCPToolError.self) { _ = try await update.handler(["start_day": .int(0)]) }
    }

    @Test("without a registered container the settings tool says the app is still starting")
    func updateRefusesWithoutDependencies() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context }, dependencies: { nil })
        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_school_calendar", in: tools).handler(["start_month": .int(8)])
        }
        // The read still answers from defaults.
        let read = try await tool(named: "school_calendar", in: tools).handler([:])
        #expect(read.contains("School year starts"))
    }
}
