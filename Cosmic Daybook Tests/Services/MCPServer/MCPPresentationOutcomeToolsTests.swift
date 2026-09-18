import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Presentation Outcomes and Batch Filing")
@MainActor
struct MCPPresentationOutcomeToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func presentations(in context: NSManagedObjectContext) -> [CDLessonAssignment] {
        context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
    }

    private func works(in context: NSManagedObjectContext) -> [CDWorkModel] {
        context.safeFetch(CDFetchRequest(CDWorkModel.self))
    }

    private func observation(
        _ student: String, _ text: String, followUp: String? = nil, detail: String? = nil
    ) -> JSONValue {
        var fields: [String: JSONValue] = ["student": .string(student), "observation": .string(text)]
        if let followUp { fields["follow_up"] = .string(followUp) }
        if let detail { fields["follow_up_detail"] = .string(detail) }
        return .object(fields)
    }

    // MARK: - Outcomes

    @Test("practice and follow_up_work create one work item each, titled from the detail")
    func practiceAndFollowUpWorkCreateWork() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)
        let oraID = try #require(ora.id)
        let ettyID = try #require(etty.id)

        let output = try await tool(named: "record_presentation", in: tools).handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Ora"), .string("Etty")]),
            "student_observations": .array([
                observation("Ora", "Needs the exchange again.", followUp: "practice"),
                observation("Etty", "Ready to multiply by two digits.", followUp: "follow_up_work",
                            detail: "Checkerboard: three two-digit problems")
            ])
        ])
        #expect(output.contains("Decisions: Ora Levi — offer practice; Etty Klein — specific follow-up work."))
        #expect(output.contains("2 work item(s) created."))

        let assignment = try #require(presentations(in: context).first)
        let created = works(in: context)
        #expect(created.count == 2)
        let oraWork = try #require(created.first { $0.studentID == oraID.uuidString })
        #expect(oraWork.kind == .practiceLesson)
        #expect(oraWork.title == "Practice: Checkerboard")
        #expect(oraWork.presentationID == assignment.id?.uuidString)
        let ettyWork = try #require(created.first { $0.studentID == ettyID.uuidString })
        #expect(ettyWork.kind == .followUpAssignment)
        #expect(ettyWork.title == "Checkerboard: three two-digit problems")
        #expect(lesson.id != nil)
    }

    @Test("re_present puts the lesson back on the child's planning list; ready_for_next_lesson confirms her")
    func rePresentAndReadyOutcomes() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math", sequence: "Operations")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)
        let oraID = try #require(ora.id)
        let ettyID = try #require(etty.id)

        _ = try await tool(named: "record_presentation", in: tools).handler([
            "lesson": .string("Stamp Game"),
            "student_names": .array([.string("Ora"), .string("Etty")]),
            "student_observations": .array([
                observation("Ora", "Lost the thread halfway.", followUp: "re_present"),
                observation("Etty", "Carried out every exchange alone.", followUp: "ready_for_next_lesson")
            ])
        ])

        let all = presentations(in: context)
        #expect(all.count == 2)
        let given = try #require(all.first { $0.isPresented })
        #expect(given.isStudentConfirmed(ettyID))
        #expect(!given.isStudentConfirmed(oraID))
        let replanned = try #require(all.first { !$0.isPresented })
        #expect(replanned.studentUUIDs == [oraID])
        #expect(works(in: context).isEmpty)
    }

    @Test("continue_observing flags the observation for the follow-up inbox")
    func continueObservingFlagsTheNote() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame", area: "Math", sequence: "Operations")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let oraID = try #require(ora.id)

        _ = try await tool(named: "record_presentation", in: tools).handler([
            "lesson": .string("Bead Frame"),
            "student_names": .array([.string("Ora")]),
            "student_observations": .array([
                observation("Ora", "Counted the beads aloud; watch whether it settles.", followUp: "continue_observing")
            ])
        ])
        let assignment = try #require(presentations(in: context).first)
        let notes = (assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []
        let note = try #require(notes.first { $0.scope == .student(oraID) })
        #expect(note.needsFollowUp)
        #expect(notes.count == 1)
    }

    @Test("an unknown follow_up value is refused and nothing is written")
    func unknownFollowUpIsRefused() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame", area: "Math", sequence: "Operations")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "record_presentation", in: tools).handler([
                "lesson": .string("Bead Frame"),
                "student_names": .array([.string("Ora")]),
                "student_observations": .array([
                    observation("Ora", "Fine.", followUp: "mastered")
                ])
            ])
        }
        #expect(presentations(in: context).isEmpty)
    }

    // MARK: - Batch

    @Test("presentations files several lessons in one call with one receipt per lesson")
    func batchFilesEveryPresentation() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication")
        CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math", sequence: "Operations")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "record_presentation", in: tools).handler([
            "presentations": .array([
                .object([
                    "lesson": .string("Checkerboard"),
                    "student_names": .array([.string("Ora")]),
                    "date": .string("2026-09-08"),
                    "group_observation": .string("Laid out the board alone.")
                ]),
                .object([
                    "lesson": .string("Stamp Game"),
                    "student_names": .array([.string("Etty"), .string("Ora")]),
                    "date": .string("2026-09-08"),
                    "student_observations": .array([
                        observation("Etty", "Exchanged without help.", followUp: "practice")
                    ])
                ])
            ])
        ])
        #expect(output.hasPrefix("Filed 2 presentation(s):"))
        #expect(output.contains("- Recorded [presentation id="))
        #expect(output.contains("Checkerboard to Ora Levi on 2026-09-08 — 1 observation(s) linked."))
        #expect(output.contains("Stamp Game to Etty Klein, Ora Levi on 2026-09-08"))
        #expect(output.contains("1 work item(s) created."))

        let all = presentations(in: context)
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.isPresented })
        #expect(works(in: context).count == 1)
    }

    @Test("a bad name anywhere in the batch writes nothing")
    func batchIsAllOrNothing() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "record_presentation", in: tools).handler([
                "presentations": .array([
                    .object([
                        "lesson": .string("Checkerboard"),
                        "student_names": .array([.string("Ora")])
                    ]),
                    .object([
                        "lesson": .string("Checkerboard"),
                        "student_names": .array([.string("Nobody")])
                    ])
                ])
            ])
        }
        #expect(presentations(in: context).isEmpty)
    }

    @Test("the batch error names the failing item")
    func batchErrorNamesTheItem() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        do {
            _ = try await tool(named: "record_presentation", in: tools).handler([
                "presentations": .array([
                    .object(["lesson": .string("Checkerboard"), "student_names": .array([.string("Ora")])]),
                    .object(["lesson": .string("Nothing Here"), "student_names": .array([.string("Ora")])])
                ])
            ])
            Issue.record("Expected the batch to be refused")
        } catch let error as MCPToolError {
            #expect(error.message.hasPrefix("presentations[1]:"))
        }
    }
}
