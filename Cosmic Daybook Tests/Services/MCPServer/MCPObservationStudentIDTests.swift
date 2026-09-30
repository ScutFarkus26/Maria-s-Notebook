import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Logic-break sweep 2026-09-29, E7: create_observation took names only, so
// two children sharing a name couldn't be told apart, though
// update_observation already took ids.
@Suite("MCP create_observation by student id")
@MainActor
struct MCPObservationStudentIDTests {

    @Test("create_observation takes a student id where two share a name")
    func createObservationTakesAnID() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Rosen")
        let goldman = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Goldman")
        CoreDataTestHelpers.save(context)
        let goldmanID = try #require(goldman.id)
        let create = try #require(tools.first { $0.name == "create_observation" })

        let output = try await create.handler([
            "student_names": .array([.string(goldmanID.uuidString)]),
            "body": .string("Built the bead stair from memory.")
        ])
        #expect(output.contains("Etty Goldman"))
        let note = try #require(context.safeFetch(CDFetchRequest(CDNote.self)).first)
        #expect(note.scope == .student(goldmanID))
    }
}
