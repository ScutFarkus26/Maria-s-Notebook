import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

// Two work items still named Naomi Levin after she withdrew (2026-09-09).
// list_students hides former students by default, so over MCP she looked like
// a child the roster did not know. New work now refuses her, in the
// repository every screen writes through and at the assign_work door.

@Suite("Work Assignment Enrollment")
@MainActor
struct WorkAssignmentEnrollmentTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    @Test("createWork refuses a withdrawn student and names her status")
    func repositoryRefusesFormerStudent() throws {
        let context = try makeContext()
        let naomi = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Naomi", lastName: "Levin", enrollmentStatus: .withdrawn
        )
        CoreDataTestHelpers.save(context)
        let repository = WorkRepository(context: context)

        #expect(throws: WorkRepository.AssignmentError.studentNotEnrolled(name: "Naomi Levin", status: "withdrawn")) {
            try repository.createWork(studentID: try #require(naomi.id), lessonID: UUID())
        }
        #expect(context.safeFetch(CDFetchRequest(CDWorkModel.self)).isEmpty)
    }

    @Test("createWork accepts an enrolled student and an id with no record on file")
    func repositoryAcceptsEnrolledAndUnknown() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.save(context)
        let repository = WorkRepository(context: context)

        _ = try repository.createWork(studentID: try #require(ora.id), lessonID: UUID())
        _ = try repository.createWork(studentID: UUID(), lessonID: UUID())
        #expect(context.safeFetch(CDFetchRequest(CDWorkModel.self)).count == 2)
    }

    @Test("assign_work refuses a former student by status and creates nothing")
    func assignWorkRefusesFormerStudent() async throws {
        let context = try makeContext()
        CoreDataTestHelpers.seedLesson(in: context, name: "Commutative Law", area: "Math", sequence: "Laws")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Naomi", lastName: "Levin", enrollmentStatus: .withdrawn
        )
        CoreDataTestHelpers.save(context)
        let tools = MCPNotebookTools.makeTools(context: { context })
        let assign = try #require(tools.first { $0.name == "assign_work" })

        await #expect(throws: MCPToolError.self) {
            try await assign.handler([
                "lesson": .string("Commutative Law"),
                "student_names": .array([.string("Ora"), .string("Naomi Levin")])
            ])
        }
        #expect(context.safeFetch(CDFetchRequest(CDWorkModel.self)).isEmpty)

        let receipt = try await assign.handler([
            "lesson": .string("Commutative Law"), "student_names": .array([.string("Ora")])
        ])
        #expect(receipt.contains("Ora Pardo"))
    }

    @Test("Work readers name a former student with her status")
    func readersMarkFormerStudents() async throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let naomi = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Naomi", lastName: "Levin", enrollmentStatus: .withdrawn
        )
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Label the product", studentID: try #require(ora.id)
        )
        for student in [ora, naomi] {
            let participant = CDWorkParticipantEntity(context: context)
            participant.studentID = try #require(student.id).uuidString
            participant.work = work
        }
        CoreDataTestHelpers.save(context)
        let tools = MCPNotebookTools.makeTools(context: { context })
        let detail = try #require(tools.first { $0.name == "work_detail" })

        let output = try await detail.handler(["work_id": .string(try #require(work.id?.uuidString))])
        #expect(output.contains("Naomi Levin (withdrawn)"))
        #expect(output.contains("Ora Pardo"))
    }
}
