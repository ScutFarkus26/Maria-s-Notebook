import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Work Removal And Reader Tools")
@MainActor
struct MCPWorkRemovalToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func addParticipant(_ student: CDStudent, to work: CDWorkModel, in context: NSManagedObjectContext) {
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = student.id?.uuidString ?? ""
        participant.work = work
    }

    /// Avigail's copy names Sarah as a passenger; Leshem's copy does not.
    private func seedPoster(
        in context: NSManagedObjectContext
    ) throws -> (avigail: CDStudent, leshem: CDStudent, sarah: CDStudent, avigailsRow: CDWorkModel, leshemsRow: CDWorkModel) {
        let avigail = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avigail", lastName: "Greenbaum")
        let leshem = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leshem", lastName: "Pardes")
        let sarah = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Zakon")
        let lessonID = UUID()
        let avigailsRow = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Fundamental Needs Poster", studentID: try #require(avigail.id), lessonID: lessonID
        )
        let leshemsRow = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Fundamental Needs Poster", studentID: try #require(leshem.id), lessonID: lessonID
        )
        for row in [avigailsRow, leshemsRow] {
            row.kind = .followUpAssignment
            addParticipant(avigail, to: row, in: context)
            addParticipant(leshem, to: row, in: context)
        }
        addParticipant(sarah, to: avigailsRow, in: context)
        CoreDataTestHelpers.save(context)
        return (avigail, leshem, sarah, avigailsRow, leshemsRow)
    }

    // MARK: - Readers

    @Test("student_work lists each linked assignment once, by the copy she owns")
    func studentWorkListsLinkedAssignmentOnce() async throws {
        let (tools, context) = try makeTools()
        let poster = try seedPoster(in: context)

        let output = try await tool(named: "student_work", in: tools).handler([
            "student_name": .string("Avigail"), "include_completed": .bool(false)
        ])
        #expect(output.contains(try #require(poster.avigailsRow.id?.uuidString)))
        #expect(!output.contains(try #require(poster.leshemsRow.id?.uuidString)))
        #expect(output.contains("with Leshem Pardes, Sarah Zakon"))

        // A passenger with no copy of her own still sees the row she is on.
        let sarahs = try await tool(named: "student_work", in: tools).handler([
            "student_name": .string("Sarah Zakon"), "include_completed": .bool(false)
        ])
        #expect(sarahs.contains(try #require(poster.avigailsRow.id?.uuidString)))
    }

    @Test("work_detail names the owner separately from the participants")
    func workDetailNamesOwner() async throws {
        let (tools, context) = try makeTools()
        let poster = try seedPoster(in: context)

        let output = try await tool(named: "work_detail", in: tools).handler([
            "work_id": .string(try #require(poster.avigailsRow.id?.uuidString))
        ])
        #expect(output.contains("Owner: Avigail Greenbaum (\(try #require(poster.avigail.id?.uuidString)))"))
        #expect(output.contains("Students: Avigail Greenbaum, Leshem Pardes, Sarah Zakon"))
    }

    @Test("work_detail lists a check-in that only carries the workID string")
    func workDetailListsDetachedCheckIn() async throws {
        let (tools, context) = try makeTools()
        let poster = try seedPoster(in: context)
        let detached = CDWorkCheckIn(context: context)
        detached.workID = try #require(poster.avigailsRow.id?.uuidString)
        detached.purpose = "Poster review"
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "work_detail", in: tools).handler([
            "work_id": .string(try #require(poster.avigailsRow.id?.uuidString))
        ])
        #expect(output.contains("Poster review"))
    }

    // MARK: - remove_student_from_work

    @Test("remove_student_from_work without confirm reports the plan and changes nothing")
    func removalWithoutConfirmOnlyReports() async throws {
        let (tools, context) = try makeTools()
        let poster = try seedPoster(in: context)

        let output = try await tool(named: "remove_student_from_work", in: tools).handler([
            "work_id": .string(try #require(poster.avigailsRow.id?.uuidString)),
            "student_name": .string("Sarah Zakon")
        ])
        #expect(output.hasPrefix("remove_student_from_work refused — nothing has been changed."))
        #expect(output.contains("she is a passenger"))
        #expect(output.contains("no completion recorded"))
        #expect(MCPNotebookTools.workStudentIDs(for: poster.avigailsRow).count == 3)
    }

    @Test("remove_student_from_work with confirm drops the passenger and leaves both copies")
    func removalWithConfirmDropsPassenger() async throws {
        let (tools, context) = try makeTools()
        let poster = try seedPoster(in: context)

        let output = try await tool(named: "remove_student_from_work", in: tools).handler([
            "work_id": .string(try #require(poster.avigailsRow.id?.uuidString)),
            "student_name": .string("Sarah Zakon"),
            "confirm": .bool(true)
        ])
        #expect(output.hasPrefix("Removed Sarah Zakon."))
        #expect(!poster.avigailsRow.isDeleted)
        #expect(!poster.leshemsRow.isDeleted)
        #expect(Set(MCPNotebookTools.workStudentIDs(for: poster.avigailsRow))
            == Set([poster.avigail.id, poster.leshem.id].compactMap { $0 }))
        #expect(WorkGrouping.group(containing: poster.avigailsRow, in: context).shape == .linkedCopies(total: 2))
    }

    @Test("remove_student_from_work names the promotion when she owns a shared row")
    func removalReportsPromotion() async throws {
        let (tools, context) = try makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let naomi = CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", lastName: "Levin")
        let row = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Commutative law", studentID: try #require(ora.id), lessonID: UUID()
        )
        addParticipant(ora, to: row, in: context)
        addParticipant(naomi, to: row, in: context)
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "remove_student_from_work", in: tools).handler([
            "work_id": .string(try #require(row.id?.uuidString)),
            "student_name": .string("Ora"),
            "confirm": .bool(true)
        ])
        #expect(output.contains("she OWNS this shared row"))
        #expect(output.contains("Naomi Levin becomes the owner"))
        #expect(!row.isDeleted)
        #expect(row.studentID == naomi.id?.uuidString)
    }

    @Test("remove_student_from_work refuses the last child on a row")
    func removalRefusesLastChild() async throws {
        let (tools, context) = try makeTools()
        let only = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let row = CoreDataTestHelpers.seedWorkModel(in: context, studentID: try #require(only.id), lessonID: UUID())
        addParticipant(only, to: row, in: context)
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            try await tool(named: "remove_student_from_work", in: tools).handler([
                "work_id": .string(try #require(row.id?.uuidString)),
                "student_name": .string("Ora"),
                "confirm": .bool(true)
            ])
        }
        #expect(!row.isDeleted)
    }
}
