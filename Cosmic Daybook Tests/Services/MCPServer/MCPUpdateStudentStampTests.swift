import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A student edit stamps `modifiedAt`: Remove Last Year keeps a private copy edited after a
/// stopped run over its older shared original (`ClassroomShareRelease.editedLater`). The
/// born-after-sunset flag is one of those edits, and `list_students` shows the Hebrew
/// birthday it moves.
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

    @Test("born_after_sunset sets and clears the flag, and each change stamps modifiedAt")
    func bornAfterSunsetSetsAndClears() async throws {
        let seed = try seeded()
        let tool = try #require(seed.tools.first { $0.name == "update_student" })
        #expect(!seed.student.bornAfterSunset)

        let setOutput = try await tool.handler(["student": .string("Maria"), "born_after_sunset": .bool(true)])
        #expect(seed.student.bornAfterSunset)
        #expect(setOutput.contains("born after sunset → yes"))
        let firstStamp = try #require(seed.student.modifiedAt)
        #expect(firstStamp > earlier)

        seed.student.modifiedAt = earlier
        CoreDataTestHelpers.save(seed.context)
        let clearOutput = try await tool.handler(["student": .string("Maria"), "born_after_sunset": .bool(false)])
        #expect(!seed.student.bornAfterSunset)
        #expect(clearOutput.contains("born after sunset → no"))
        let secondStamp = try #require(seed.student.modifiedAt)
        #expect(secondStamp > earlier)
    }

    // Hebcal: 2015-03-04 = 13 Adar 5775, 2015-03-05 = 14 Adar 5775 (Purim).
    @Test("list_students shows the Hebrew birthday, a day later for a child born after sunset")
    func listStudentsShowsHebrewBirthday() async throws {
        let seed = try seeded()
        let update = try #require(seed.tools.first { $0.name == "update_student" })
        let list = try #require(seed.tools.first { $0.name == "list_students" })

        _ = try await update.handler(["student": .string("Maria"), "birthday": .string("2015-03-04")])
        #expect(try await list.handler([:]).contains("born 2015-03-04 (13 Adar 5775), age "))

        _ = try await update.handler(["student": .string("Maria"), "born_after_sunset": .bool(true)])
        #expect(try await list.handler([:]).contains("born 2015-03-04 (14 Adar 5775), age "))
    }

    @Test("list_students names no Hebrew birthday when there is no birthday")
    func listStudentsWithoutBirthday() async throws {
        let seed = try seeded()
        seed.student.birthday = nil
        CoreDataTestHelpers.save(seed.context)
        let list = try #require(seed.tools.first { $0.name == "list_students" })
        let output = try await list.handler([:])
        #expect(output.contains("Maria Montessori"))
        #expect(!output.contains("born"))
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
