import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A student edit stamps `modifiedAt`: Remove Last Year keeps a private copy edited after a
/// stopped run over its older shared original (`ClassroomShareRelease.editedLater`).
@Suite("update_student stamps modifiedAt")
@MainActor
struct MCPUpdateStudentStampTests {
    private let earlier = Date(timeIntervalSince1970: 1_750_000_000)

    private struct Seeded {
        let context: NSManagedObjectContext
        let student: CDStudent
        var tools: [MCPToolDefinition] { MCPNotebookTools.makeTools(context: { context }) }
    }

    private func seeded() throws -> Seeded {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maria", lastName: "Montessori")
        student.modifiedAt = earlier
        CoreDataTestHelpers.save(context)
        return Seeded(context: context, student: student)
    }

    @Test("An edit through update_student moves modifiedAt on")
    func editStamps() async throws {
        let seed = try seeded()
        let tool = try #require(seed.tools.first { $0.name == "update_student" })
        _ = try await tool.handler(["student": .string("Maria"), "nickname": .string("Mimi")])
        let stamped = try #require(seed.student.modifiedAt)
        #expect(stamped > earlier)
    }

    @Test("An edit that changes nothing leaves modifiedAt alone")
    func sameValuesDontStamp() throws {
        let seed = try seeded()
        let id = try #require(seed.student.id)
        let repository = StudentRepository(context: seed.context)
        #expect(repository.updateStudent(id: id, firstName: "Maria", lastName: "Montessori"))
        #expect(seed.student.modifiedAt == earlier)
    }
}
