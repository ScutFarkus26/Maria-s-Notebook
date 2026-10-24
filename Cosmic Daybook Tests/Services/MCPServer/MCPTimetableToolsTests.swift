import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// weekly_schedules, set_timetable and change_schedule_day, round-tripped
/// against an in-memory store.
@Suite("MCP Timetable Tools")
@MainActor
struct MCPTimetableToolsTests {
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

    private let classWeek: JSONValue = [
        ["weekdays": ["Monday", "Tuesday"], "start": "9:00", "length_minutes": 45, "title": "Circle"],
        ["weekdays": ["Friday"], "start": "1:15", "end": "2:00", "title": "Clean-up", "note": "Early day"]
    ]

    // MARK: - set_timetable

    @Test("set_timetable previews first, then writes the lane's week on confirm")
    func setTimetableConfirmGate() async throws {
        let (tools, context) = try makeTools()
        seedLanes(in: context)

        let preview = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-10-26", "blocks": classWeek
        ], in: tools)
        #expect(preview.contains("refused"))
        #expect(preview.contains("Monday 9:00–9:45 Circle"))
        #expect(blocks(of: "Our class", in: context).isEmpty)

        let receipt = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-10-26", "blocks": classWeek, "confirm": true
        ], in: tools)
        #expect(receipt.contains("3 blocks on 3 days"))
        let stored = blocks(of: "Our class", in: context)
        #expect(stored.count == 3)
        let friday = try #require(stored.first { $0.weekday == .friday })
        // "1:15" with no am or pm is the afternoon.
        #expect(friday.startMinute == 13 * 60 + 15)
        #expect(friday.lengthMinutes == 45)
        #expect(friday.note == "Early day")
        #expect(!context.hasChanges)
    }

    @Test("set_timetable replaces from a day on and leaves the weeks before it as they were")
    func setTimetableKeepsThePast() async throws {
        let (tools, context) = try makeTools()
        seedLanes(in: context)
        _ = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-10-19", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "9:00", "length_minutes": 30, "title": "Old"]]
        ], in: tools)
        let receipt = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-10-26", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "10:00", "length_minutes": 30, "title": "New"]]
        ], in: tools)
        #expect(receipt.contains("1 earlier block end"))

        let before = try await call("weekly_schedules", ["date": "2026-10-19"], in: tools)
        let after = try await call("weekly_schedules", ["date": "2026-10-26"], in: tools)
        #expect(before.contains("Old") && !before.contains("New"))
        #expect(after.contains("New") && !after.contains("Old"))
    }

    @Test("set_timetable names the children, and asks for a full name when two share a first name")
    func setTimetableChildren() async throws {
        let (tools, context) = try makeTools()
        seedLanes(in: context)
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Adler")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Levy")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)

        let ambiguous = await #expect(throws: MCPToolError.self) {
            _ = try await call("set_timetable", [
                "lane": "Morah Devora", "confirm": true,
                "blocks": [["weekdays": ["Monday"], "start": "10:00", "length_minutes": 30,
                            "title": "Hebrew", "children": ["Sarah"]]]
            ], in: tools)
        }
        #expect(ambiguous?.message.contains("Block 1") == true)
        #expect(ambiguous?.message.contains("More than one student") == true)
        #expect(blocks(of: "Morah Devora", in: context).isEmpty)

        _ = try await call("set_timetable", [
            "lane": "Devora", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "10:00", "length_minutes": 30,
                        "title": "Hebrew", "children": ["Sarah Levy", "Maya"]]]
        ], in: tools)
        let read = try await call("weekly_schedules", ["lane": "Morah Devora"], in: tools)
        #expect(read.contains("with Sarah Levy, Maya Soto") || read.contains("with Maya Soto, Sarah Levy"))
        #expect(!read.contains("Adler"))
    }

    @Test("set_timetable makes a person lane only when asked, and refuses bad times and weekdays")
    func setTimetableLanesAndValidation() async throws {
        let (tools, context) = try makeTools()
        seedLanes(in: context)
        let week: JSONValue = [["weekdays": ["Monday"], "start": "9:00", "length_minutes": 30, "title": "Art"]]

        let missing = await #expect(throws: MCPToolError.self) {
            _ = try await call("set_timetable", ["lane": "Music teacher", "blocks": week, "confirm": true], in: tools)
        }
        #expect(missing?.message.contains("No lane named") == true)
        #expect(TimetableService.lanes(in: context).count == 4)

        _ = try await call("set_timetable", [
            "lane": "Music teacher", "blocks": week, "confirm": true, "create_lane": true
        ], in: tools)
        let lane = try #require(TimetableService.lanes(in: context).first { $0.name == "Music teacher" })
        #expect(lane.kind == .person)

        for bad in [
            ["weekdays": ["Moonday"], "start": "9:00", "length_minutes": 30],
            ["weekdays": ["Monday"], "start": "9:75", "length_minutes": 30],
            ["weekdays": ["Monday"], "start": "9:00"],
            ["weekdays": ["Monday"], "start": "9:00", "end": "8:00"]
        ] as [[String: JSONValue]] {
            await #expect(throws: MCPToolError.self) {
                _ = try await call("set_timetable", ["lane": "Our class", "blocks": [.object(bad)], "confirm": true], in: tools)
            }
        }
        #expect(blocks(of: "Our class", in: context).isEmpty)
    }

    // MARK: - weekly_schedules

    @Test("weekly_schedules lists the lanes' weeks, filtered by lane and weekday")
    func weeklySchedulesLists() async throws {
        let (tools, context) = try makeTools()
        #expect(try await call("weekly_schedules", [:], in: tools).contains("No timetable is set up"))
        seedLanes(in: context)
        _ = try await call("set_timetable", ["lane": "Our class", "blocks": classWeek, "confirm": true], in: tools)

        let all = try await call("weekly_schedules", [:], in: tools)
        #expect(all.contains("Our class — room"))
        #expect(all.contains("Danny — person, the guide"))
        #expect(all.contains("1:15–2:00 Clean-up"))

        let monday = try await call("weekly_schedules", ["lane": "our class", "weekday": "Monday"], in: tools)
        #expect(monday.contains("Circle"))
        #expect(!monday.contains("Clean-up"))
        #expect(!monday.contains("Danny"))
    }

    @Test("weekly_schedules with a date shows the day resolved: changes, turns, lessons by name, warnings")
    func weeklySchedulesResolvesADay() async throws {
        let (tools, context) = try makeTools()
        seedLanes(in: context)
        let ari = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ari", lastName: "Bell", level: .adolescent)
        CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads", area: "Math", sequence: "Decimal")
        CoreDataTestHelpers.save(context)
        _ = try await call("set_timetable", [
            "lane": "Adolescent room", "from": "2026-09-14", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "9:00", "length_minutes": 60,
                        "title": "Humanities", "teacher": "Danny"]]
        ], in: tools)
        _ = try await call("schedule_presentation", [
            "lesson": "Golden Beads", "student_names": [.string("Ari Bell")], "date": "2026-09-14"
        ], in: tools)
        _ = ari

        let day = try await call("weekly_schedules", ["date": "2026-09-14"], in: tools)
        #expect(day.contains("In Adolescent room: 9:00–10:00 Humanities"))
        #expect(day.contains("taught by Danny"))
        // The lesson is all adolescent, so it sits inside his turn, with its name.
        #expect(day.contains("Golden Beads"))
        #expect(day.contains("Ari Bell"))

        let none = try await call("weekly_schedules", ["date": "2026-09-19"], in: tools)
        #expect(none.contains("no school"))
    }

    // MARK: - change_schedule_day

    @Test("change_schedule_day cancels, changes, adds a one-off and undoes, for one day only")
    func changeScheduleDayRoundTrip() async throws {
        let (tools, context) = try makeTools()
        seedLanes(in: context)
        _ = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-09-01", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "9:00", "length_minutes": 45, "title": "Circle"],
                       ["weekdays": ["Monday"], "start": "10:00", "length_minutes": 45, "title": "Work period"]]
        ], in: tools)

        let cancelled = try await call("change_schedule_day", [
            "date": "2026-09-14", "action": "cancel", "lane": "Our class", "block_title": "circle"
        ], in: tools)
        #expect(cancelled.contains("Cancelled 9:00–9:45 Circle on Monday 2026-09-14 only"))
        let day = try await call("weekly_schedules", ["date": "2026-09-14", "lane": "Our class"], in: tools)
        #expect(!day.contains("Circle"))
        #expect(day.contains("1 change today"))
        let nextWeek = try await call("weekly_schedules", ["date": "2026-09-21", "lane": "Our class"], in: tools)
        #expect(nextWeek.contains("Circle"))

        let changed = try await call("change_schedule_day", [
            "date": "2026-09-14", "action": "change", "lane": "Our class", "block_start": "10:00",
            "start": "10:30", "title": "Work period (short)"
        ], in: tools)
        #expect(changed.contains("now 10:30–11:15 Work period (short)"))
        // A second change keeps the first one's time.
        _ = try await call("change_schedule_day", [
            "date": "2026-09-14", "action": "change", "lane": "Our class", "block_start": "10:00",
            "note": "Bring pencils"
        ], in: tools)
        let after = try await call("weekly_schedules", ["date": "2026-09-14", "lane": "Our class"], in: tools)
        #expect(after.contains("10:30–11:15 Work period (short)"))
        #expect(after.contains("changed today"))
        #expect(after.contains("Bring pencils"))

        let added = try await call("change_schedule_day", [
            "date": "2026-09-14", "action": "add", "lane": "Our class", "start": "1:00",
            "length_minutes": 30, "title": "Early dismissal"
        ], in: tools)
        #expect(added.contains("Added 1:00–1:30 Early dismissal to Our class"))

        let undone = try await call("change_schedule_day", [
            "date": "2026-09-14", "action": "undo", "lane": "Our class", "block_title": "work period"
        ], in: tools)
        #expect(undone.contains("Took away the change"))

        let refused = try await call("change_schedule_day", ["date": "2026-09-14", "action": "undo"], in: tools)
        #expect(refused.contains("refused"))
        let everything = try await call("change_schedule_day", [
            "date": "2026-09-14", "action": "undo", "confirm": true
        ], in: tools)
        #expect(everything.contains("Took away 1 change"))
        let end = try await call("weekly_schedules", ["date": "2026-09-14", "lane": "Our class"], in: tools)
        #expect(end.contains("Circle") && end.contains("Early dismissal"))
        #expect(!context.hasChanges)

        // Cancelling the one-off removes it.
        let removed = try await call("change_schedule_day", [
            "date": "2026-09-14", "action": "cancel", "lane": "Our class", "block_title": "dismissal"
        ], in: tools)
        #expect(removed.contains("Removed the one-off"))
    }

    @Test("Out Today takes a person's blocks off the day and shows their turn as out")
    func outToday() async throws {
        let (tools, context) = try makeTools()
        seedLanes(in: context)
        _ = try await call("set_timetable", [
            "lane": "Adolescent room", "from": "2026-09-01", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "9:00", "length_minutes": 60,
                        "title": "Humanities", "teacher": "Morah Devora"]]
        ], in: tools)

        let receipt = try await call("change_schedule_day", [
            "date": "2026-09-14", "action": "out", "lane": "Devora"
        ], in: tools)
        #expect(receipt.contains("Morah Devora is out on Monday 2026-09-14"))
        let day = try await call("weekly_schedules", ["date": "2026-09-14"], in: tools)
        #expect(day.contains("Morah Devora — out today"))
        #expect(day.contains("Humanities") && day.contains("— out"))

        let again = try await call("change_schedule_day", [
            "date": "2026-09-14", "action": "out", "lane": "Morah Devora"
        ], in: tools)
        #expect(again.contains("already out"))
        let back = try await call("change_schedule_day", [
            "date": "2026-09-14", "action": "back_in", "lane": "Morah Devora"
        ], in: tools)
        #expect(back.contains("is back in"))
        let restored = try await call("weekly_schedules", ["date": "2026-09-14"], in: tools)
        #expect(!restored.contains("out today"))
    }

    @Test("change_schedule_day refuses a day with no school, a room going out, and an unclear block")
    func changeScheduleDayRefusals() async throws {
        let (tools, context) = try makeTools()
        seedLanes(in: context)
        _ = try await call("set_timetable", [
            "lane": "Our class", "from": "2026-09-01", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "9:00", "length_minutes": 30, "title": "Circle"],
                       ["weekdays": ["Monday"], "start": "9:00", "length_minutes": 30, "title": "Circle two"]]
        ], in: tools)

        let weekend = await #expect(throws: MCPToolError.self) {
            _ = try await call("change_schedule_day", [
                "date": "2026-09-19", "action": "add", "lane": "Our class", "start": "9:00",
                "length_minutes": 30, "title": "Trip"
            ], in: tools)
        }
        #expect(weekend?.message.contains("School is not in session") == true)

        let room = await #expect(throws: MCPToolError.self) {
            _ = try await call("change_schedule_day", [
                "date": "2026-09-14", "action": "out", "lane": "Our class"
            ], in: tools)
        }
        #expect(room?.message.contains("is a room") == true)

        let unclear = await #expect(throws: MCPToolError.self) {
            _ = try await call("change_schedule_day", [
                "date": "2026-09-14", "action": "cancel", "lane": "Our class", "block_title": "circle"
            ], in: tools)
        }
        #expect(unclear?.message.contains("More than one block") == true)
        #expect(TimetableService.changes(
            from: TimetableTestSupport.day(2026, 9, 14), through: TimetableTestSupport.day(2026, 9, 14), in: context
        ).isEmpty)
    }
}
