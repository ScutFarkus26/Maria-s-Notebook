import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Claude's tools and a child who has left (domain logic review 2026-11-20,
/// R7): `update_work` leaves a departed child's copy as she left it, and
/// `update_student` leaves or re-enrolls through the one write of status and
/// last day, cascade and all.
@Suite("MCP tools and departed students")
@MainActor
struct MCPDepartedStudentToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private var yesterday: Date { AppCalendar.addingDays(-1, to: AppCalendar.startOfDay(Date())) }

    @Test("update_work for everyone doesn't close the copy of a child who has left")
    func departedCopyStaysOpen() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Volcano Study", area: "Science", sequence: "Geology")
        let sam = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        let ava = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ava", lastName: "Bloom")
        CoreDataTestHelpers.save(context)
        _ = try await tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Volcano Study"),
            "student_names": .array([.string("Sam"), .string("Ava")])
        ])
        let works = context.safeFetch(CDFetchRequest(CDWorkModel.self))
        let samsCopy = try #require(works.first { $0.studentID == sam.id?.uuidString })
        let avasCopy = try #require(works.first { $0.studentID == ava.id?.uuidString })
        ava.enrollmentStatus = .withdrawn
        ava.dateWithdrawn = yesterday
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "update_work", in: tools).handler([
            "work_id": .string(try #require(samsCopy.id).uuidString),
            "status": .string("complete")
        ])
        #expect(samsCopy.status == .done)
        #expect(avasCopy.status == .active)
    }

    @Test("update_work still closes the copy of a child whose last day hasn't come")
    func leavingLaterCopyCloses() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Volcano Study", area: "Science", sequence: "Geology")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        let ava = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ava", lastName: "Bloom")
        CoreDataTestHelpers.save(context)
        _ = try await tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Volcano Study"),
            "student_names": .array([.string("Sam"), .string("Ava")])
        ])
        let works = context.safeFetch(CDFetchRequest(CDWorkModel.self))
        ava.enrollmentStatus = .withdrawn
        ava.dateWithdrawn = AppCalendar.addingDays(3, to: Date())
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "update_work", in: tools).handler([
            "work_id": .string(try #require(works.first?.id).uuidString),
            "status": .string("complete")
        ])
        #expect(works.allSatisfy { $0.status == .done })
    }

    @Test("assign_work gives work to a child whose last day is still ahead, and refuses one who has left")
    func assignWorkFollowsHerLastDay() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Volcano Study", area: "Science", sequence: "Geology")
        let ava = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ava", lastName: "Bloom")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Fine")
        ava.enrollmentStatus = .withdrawn
        ava.dateWithdrawn = AppCalendar.addingDays(3, to: Date())
        ora.enrollmentStatus = .transferred
        ora.dateWithdrawn = yesterday
        CoreDataTestHelpers.save(context)
        let assign = try tool(named: "assign_work", in: tools)

        _ = try await assign.handler([
            "lesson": .string("Volcano Study"), "student_names": .array([.string("Ava")])
        ])
        let works = context.safeFetch(CDFetchRequest(CDWorkModel.self))
        #expect(works.map(\.studentID) == [try #require(ava.id).uuidString])

        await #expect(throws: (any Error).self) {
            _ = try await assign.handler([
                "lesson": .string("Volcano Study"), "student_names": .array([.string("Ora")])
            ])
        }
        #expect(context.safeFetch(CDFetchRequest(CDWorkModel.self)).count == 1)
    }

    @Test("update_student takes a child out with her last day, and back in, un-skipping her year plan")
    func updateStudentLeavesAndComesBack() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        let mayaID = try #require(maya.id)
        defer { DepartureSkipLedger.synced.clear(for: mayaID) }
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = mayaID.uuidString
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = AppCalendar.addingDays(30, to: Date())
        entry.sequenceGroupKey = "Geometry::Quadrilaterals"
        entry.statusRaw = YearPlanEntryStatus.planned.rawValue
        CoreDataTestHelpers.save(context)
        let update = try tool(named: "update_student", in: tools)

        let lastDay = AppCalendar.addingDays(2, to: AppCalendar.startOfDay(Date()))
        let leaving = try await update.handler([
            "student": .string("Maya"),
            "enrollment": .string("withdrawn"),
            "last_day": .string(MCPNotebookTools.isoDay.string(from: lastDay))
        ])
        #expect(maya.enrollmentStatus == .withdrawn)
        #expect(maya.dateWithdrawn.map(AppCalendar.startOfDay) == lastDay)
        #expect(entry.status == .skipped)
        #expect(leaving.lowercased().contains("withdrawn, last day"))
        #expect(leaving.contains("1 year-plan entry skipped"))

        let back = try await update.handler(["student": .string("Maya"), "enrollment": .string("enrolled")])
        #expect(maya.enrollmentStatus == .enrolled)
        #expect(maya.dateWithdrawn == nil)
        #expect(entry.status == .planned)
        #expect(back.contains("1 year-plan entry back to planned"))
    }

    @Test("update_student refuses a last day for a child who is enrolled")
    func lastDayNeedsDeparture() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        CoreDataTestHelpers.save(context)
        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_student", in: tools).handler([
                "student": .string("Maya"), "last_day": .string("2026-12-18")
            ])
        }
        #expect(maya.enrollmentStatus == .enrolled)
        #expect(maya.dateWithdrawn == nil)
    }
}
