import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// change_schedule_day and set_timetable saying what they do (the 2026-10-29
/// bug hunt): a block named by id must be on the date, and set_timetable's
/// report lists the one-day changes it drops and says when its first day is
/// already past.
@Suite("MCP Timetable Tools: the day named, and what goes")
@MainActor
struct MCPTimetableDayChecksTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func call(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> String {
        let tool = try #require(tools.first { $0.name == name })
        return try await tool.handler(arguments)
    }

    /// The starter lanes (Our class, Adolescent room, Danny) and Morah Devora.
    private func seedLanes(in context: NSManagedObjectContext) {
        for lane in TimetableService.makeStarterLanes(in: context) where lane.isGuide {
            TimetableService.rename(lane, to: "Danny")
        }
        TimetableService.addPerson(named: "Morah Devora", in: context)
        CoreDataTestHelpers.save(context)
    }

    private func blocks(of laneName: String, in context: NSManagedObjectContext) -> [CDTimetableBlock] {
        TimetableService.lanes(in: context).first { $0.name == laneName }
            .map { TimetableService.blocks(of: $0, in: context) } ?? []
    }

    @Test("change_schedule_day refuses a block_id that isn't on the date, and changes nothing")
    func changeScheduleDayBlockMustBeOnTheDay() async throws {
        let (tools, context) = try makeTools()
        seedLanes(in: context)
        _ = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-09-01", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "9:00", "length_minutes": 45, "title": "Circle"]]
        ], in: tools)
        _ = try await call("change_schedule_day", [
            "date": "2026-09-15", "action": "add", "lane": "Our class", "start": "1:00",
            "length_minutes": 30, "title": "Assembly"
        ], in: tools)
        let circle = try #require(blocks(of: "Our class", in: context).first { $0.title == "Circle" })
        let assembly = try #require(blocks(of: "Our class", in: context).first { $0.title == "Assembly" })
        let circleID = JSONValue.string(try #require(circle.id?.uuidString))
        let assemblyID = JSONValue.string(try #require(assembly.id?.uuidString))

        // A one-off on Tuesday, named on Monday: neither removed nor changed there.
        let removeOther = await #expect(throws: MCPToolError.self) {
            _ = try await call("change_schedule_day", [
                "date": "2026-09-14", "action": "cancel", "block_id": assemblyID
            ], in: tools)
        }
        #expect(removeOther?.message.contains("is a one-off on Tuesday 2026-09-15, not on Monday 2026-09-14") == true)
        let changeOther = await #expect(throws: MCPToolError.self) {
            _ = try await call("change_schedule_day", [
                "date": "2026-09-14", "action": "change", "block_id": assemblyID, "title": "Trip"
            ], in: tools)
        }
        #expect(changeOther?.message.contains("nothing was changed") == true)
        #expect(!assembly.isDeleted && assembly.title == "Assembly")

        // A Monday block on a Tuesday would get a change no day reads.
        let wrongWeekday = await #expect(throws: MCPToolError.self) {
            _ = try await call("change_schedule_day", [
                "date": "2026-09-15", "action": "cancel", "block_id": circleID
            ], in: tools)
        }
        #expect(wrongWeekday?.message.contains("is on Mondays") == true)
        let undoWrongDay = await #expect(throws: MCPToolError.self) {
            _ = try await call("change_schedule_day", [
                "date": "2026-09-15", "action": "undo", "block_id": circleID
            ], in: tools)
        }
        #expect(undoWrongDay?.message.contains("is on Mondays") == true)
        #expect(context.safeFetch(CDFetchRequest(CDTimetableChange.self)).isEmpty)

        // On its own day, block_id works as before.
        let cancelled = try await call("change_schedule_day", [
            "date": "2026-09-14", "action": "cancel", "block_id": circleID
        ], in: tools)
        #expect(cancelled.contains("Cancelled 9:00–9:45 Circle on Monday 2026-09-14 only"))
        let removed = try await call("change_schedule_day", [
            "date": "2026-09-15", "action": "cancel", "block_id": assemblyID
        ], in: tools)
        #expect(removed.contains("Removed the one-off"))
    }

    @Test("change_schedule_day refuses a block_id after the block ended, or before it starts")
    func changeScheduleDayBlockMustBeRunning() async throws {
        let (tools, context) = try makeTools()
        seedLanes(in: context)
        _ = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-09-01", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "9:00", "length_minutes": 45, "title": "Circle"]]
        ], in: tools)
        let circle = try #require(blocks(of: "Our class", in: context).first { $0.title == "Circle" })
        let circleID = JSONValue.string(try #require(circle.id?.uuidString))
        _ = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-09-21", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "9:15", "length_minutes": 30, "title": "Meeting"]]
        ], in: tools)
        let ended = await #expect(throws: MCPToolError.self) {
            _ = try await call("change_schedule_day", [
                "date": "2026-09-28", "action": "change", "block_id": circleID, "start": "10:00"
            ], in: tools)
        }
        #expect(ended?.message.contains("ended on Sunday 2026-09-20") == true)

        let meeting = try #require(blocks(of: "Our class", in: context).first { $0.title == "Meeting" })
        let meetingID = JSONValue.string(try #require(meeting.id?.uuidString))
        let early = await #expect(throws: MCPToolError.self) {
            _ = try await call("change_schedule_day", [
                "date": "2026-09-14", "action": "cancel", "block_id": meetingID
            ], in: tools)
        }
        #expect(early?.message.contains("starts on Monday 2026-09-21") == true)
        #expect(context.safeFetch(CDFetchRequest(CDTimetableChange.self)).isEmpty)
    }

    @Test("set_timetable lists the one-day changes it drops, and says when its first day is already past")
    func setTimetableListsWhatGoes() async throws {
        let (tools, context) = try makeTools()
        seedLanes(in: context)
        _ = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-09-01", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "9:00", "length_minutes": 45, "title": "Circle"]]
        ], in: tools)
        // One change before the new week, two after it.
        for (date, action) in [("2026-09-14", "cancel"), ("2026-09-28", "cancel"), ("2026-09-21", "change")] {
            _ = try await call("change_schedule_day", [
                "date": .string(date), "action": .string(action), "lane": "Our class", "block_title": "circle",
                "start": "10:00"
            ], in: tools)
        }
        let newWeek: JSONValue = [["weekdays": ["Monday"], "start": "9:15", "length_minutes": 30, "title": "Meeting"]]

        let preview = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-09-21", "blocks": newWeek
        ], in: tools)
        #expect(preview.contains("refused"))
        #expect(preview.contains("- Monday 2026-09-21: 9:00–9:45 Circle, changed to 10:00–10:45 Circle"))
        #expect(preview.contains("- Monday 2026-09-28: 9:00–9:45 Circle, cancelled"))
        #expect(!preview.contains("2026-09-14:"), "a change before the new week stays")
        #expect(preview.contains("Monday 2026-09-21 is already past"))
        #expect(!preview.contains("weeks already past keep them"))

        // A first day still to come says only that the days before it keep the old week.
        let later = try #require(AppCalendar.shared.date(byAdding: .day, value: 14, to: Date()))
        let ahead = try await call("set_timetable", [
            "lane": "Our class", "from": .string(MCPNotebookTools.dayString(later)), "blocks": newWeek
        ], in: tools)
        #expect(ahead.contains("keep the old week"))
        #expect(!ahead.contains("already past"))

        let receipt = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-09-21", "blocks": newWeek, "confirm": true
        ], in: tools)
        #expect(receipt.contains("1 earlier block ends the day before, with 2 one-day changes of its own"))
        let left = context.safeFetch(CDFetchRequest(CDTimetableChange.self))
        #expect(left.count == 1)
        #expect(left.first?.day == TimetableTestSupport.day(2026, 9, 14))
    }
}
