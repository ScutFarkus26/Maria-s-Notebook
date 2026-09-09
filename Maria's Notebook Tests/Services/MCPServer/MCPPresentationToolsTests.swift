import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("MCP Presentation Tools")
@MainActor
struct MCPPresentationToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        return (tools, context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func presentations(in context: NSManagedObjectContext) -> [CDLessonAssignment] {
        context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
    }

    // MARK: - find_lessons

    @Test("find_lessons ranks an exact name above a partial match")
    func findLessonsRanksExactNameFirst() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Racks and Tubes", area: "Math", sequence: "Division")
        CoreDataTestHelpers.seedLesson(
            in: context, name: "Racks and Tubes Follow-Up", area: "Math", sequence: "Division"
        )
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "find_lessons", in: tools).handler([
            "query": .string("racks and tubes")
        ])
        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].contains("Racks and Tubes —"))
        #expect(lines[0].contains("Math › Division"))
        #expect(lines[1].contains("Racks and Tubes Follow-Up"))
    }

    @Test("find_lessons matches on area and reports a miss")
    func findLessonsMatchesAreaAndReportsMiss() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Bells", area: "Music", sequence: "Tone Bars")
        CoreDataTestHelpers.save(context)

        let byArea = try await tool(named: "find_lessons", in: tools).handler(["query": .string("music")])
        #expect(byArea.contains("Bells"))

        let miss = try await tool(named: "find_lessons", in: tools).handler(["query": .string("astronomy")])
        #expect(miss.contains("No lessons matched"))
    }

    // MARK: - record_presentation

    @Test("record_presentation files the lesson with group and per-student observations")
    func recordPresentationWritesPresentationAndNotes() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Racks and Tubes", area: "Math", sequence: "Division"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)
        let lessonID = try #require(lesson.id)
        let oraID = try #require(ora.id)
        let ettyID = try #require(etty.id)

        let output = try await tool(named: "record_presentation", in: tools).handler([
            "lesson": .string("Racks and Tubes"),
            "student_names": .array([.string("Ora"), .string("Etty")]),
            "date": .string("2026-09-03"),
            "group_observation": .string("Both followed the exchange without prompting."),
            "student_observations": .array([
                .object([
                    "student": .string("Ora"),
                    "observation": .string("Set the racks out herself and named each hierarchy.")
                ]),
                .object([
                    "student": .string("Etty"),
                    "observation": .string("Lost the place when borrowing; wants it again."),
                    "needs_follow_up": .bool(true)
                ])
            ])
        ])
        #expect(output.contains("Recorded [presentation id="))
        #expect(output.contains("Racks and Tubes"))
        #expect(output.contains("2026-09-03"))
        #expect(output.contains("3 observation(s) linked"))

        let assignments = presentations(in: context)
        #expect(assignments.count == 1)
        let assignment = try #require(assignments.first)
        #expect(assignment.isPresented)
        #expect(assignment.lessonIDUUID == lessonID)
        #expect(Set(assignment.studentUUIDs) == [oraID, ettyID])
        #expect(MCPNotebookTools.dayString(assignment.presentedAt) == "2026-09-03")

        let notes = (assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []
        #expect(notes.count == 3)
        // A back-dated presentation dates its observations to that day.
        #expect(notes.allSatisfy { MCPNotebookTools.dayString($0.createdAt) == "2026-09-03" })

        let ettyNote = try #require(notes.first { $0.scope == .student(ettyID) })
        #expect(ettyNote.needsFollowUp)
        let oraNote = try #require(notes.first { $0.scope == .student(oraID) })
        #expect(!oraNote.needsFollowUp)
        let groupScope = NoteScope.students([oraID, ettyID].sorted { $0.uuidString < $1.uuidString })
        let groupNote = try #require(notes.first { $0.scope == groupScope })
        #expect(groupNote.body == "Both followed the exchange without prompting.")
    }

    @Test("record_presentation completes the lesson already planned for those students")
    func recordPresentationCompletesPlannedLesson() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads", area: "Math", sequence: "Addition"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let planned = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ora], scheduledFor: Date(), context: context
        )
        CoreDataTestHelpers.save(context)
        let plannedID = try #require(planned.id)

        let output = try await tool(named: "record_presentation", in: tools).handler([
            "lesson": .string("Golden Beads"),
            "student_names": .array([.string("Ora")])
        ])
        #expect(output.contains("Recorded the lesson planned for them"))
        #expect(output.contains(plannedID.uuidString))

        let assignments = presentations(in: context)
        #expect(assignments.count == 1)
        let recorded = try #require(assignments.first)
        #expect(recorded.isPresented)
        #expect(recorded.id == plannedID)
    }

    @Test("record_presentation re-filed for the same day updates rather than duplicating")
    func recordPresentationIsIdempotentForTheSameDay() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads", area: "Math", sequence: "Addition")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        let arguments: [String: JSONValue] = [
            "lesson": .string("Golden Beads"),
            "student_names": .array([.string("Ora")]),
            "date": .string("2026-09-03"),
            "group_observation": .string("Carried the exchange on her own.")
        ]
        let first = try await tool(named: "record_presentation", in: tools).handler(arguments)
        #expect(first.contains("Recorded [presentation id="))

        let second = try await tool(named: "record_presentation", in: tools).handler(arguments)
        #expect(second.contains("Updated the presentation already recorded"))

        let assignments = presentations(in: context)
        #expect(assignments.count == 1)
        // The identical observation is not written a second time.
        let assignment = try #require(assignments.first)
        let notes = (assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []
        #expect(notes.count == 1)
    }

    @Test("record_presentation rejects an observation for a child who was not present")
    func recordPresentationRejectsUnlistedStudentObservation() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads", area: "Math", sequence: "Addition")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "record_presentation", in: tools).handler([
                "lesson": .string("Golden Beads"),
                "student_names": .array([.string("Ora")]),
                "student_observations": .array([
                    .object([
                        "student": .string("Etty"),
                        "observation": .string("Watched from the next table.")
                    ])
                ])
            ])
        }
        #expect(presentations(in: context).isEmpty)
    }

    @Test("record_presentation asks which lesson when the name is ambiguous")
    func recordPresentationReportsAmbiguousLesson() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Bead Chains: Short", area: "Math", sequence: "Chains")
        CoreDataTestHelpers.seedLesson(in: context, name: "Bead Chains: Long", area: "Math", sequence: "Chains")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        let error = await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "record_presentation", in: tools).handler([
                "lesson": .string("bead chains"),
                "student_names": .array([.string("Ora")])
            ])
        }
        let message = try #require(error?.message)
        #expect(message.contains("More than one lesson matches"))
        #expect(message.contains("Bead Chains: Short"))
        #expect(message.contains("Bead Chains: Long"))
        #expect(presentations(in: context).isEmpty)
    }

    @Test("record_presentation reports a lesson that is not in the curriculum")
    func recordPresentationReportsUnknownLesson() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        let error = await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "record_presentation", in: tools).handler([
                "lesson": .string("Trinomial Cube"),
                "student_names": .array([.string("Ora")])
            ])
        }
        let message = try #require(error?.message)
        #expect(message.contains("find_lessons"))
    }

    @Test("record_presentation accepts a lesson id and a partial name")
    func recordPresentationAcceptsIDAndPartialName() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Racks and Tubes", area: "Math", sequence: "Division"
        )
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)
        let lessonID = try #require(lesson.id)

        let byID = try await tool(named: "record_presentation", in: tools).handler([
            "lesson": .string(lessonID.uuidString),
            "student_names": .array([.string("Ora")])
        ])
        #expect(byID.contains("Racks and Tubes"))

        let byPartialName = try await tool(named: "record_presentation", in: tools).handler([
            "lesson": .string("racks"),
            "student_names": .array([.string("Etty")])
        ])
        #expect(byPartialName.contains("Racks and Tubes"))
        #expect(presentations(in: context).count == 2)
    }

    @Test("update_observation keeps a note attached to its presentation when children change")
    func reassigningAPresentationNoteKeepsTheLink() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(
            in: context, name: "Racks and Tubes", area: "Math", sequence: "Division"
        )
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)
        let ettyID = try #require(etty.id)

        _ = try await tool(named: "record_presentation", in: tools).handler([
            "lesson": .string("Racks and Tubes"),
            "student_names": .array([.string("Ora")]),
            "student_observations": .array([
                .object([
                    "student": .string("Ora"),
                    "observation": .string("Named each hierarchy without prompting.")
                ])
            ])
        ])
        let assignment = try #require(presentations(in: context).first)
        let note = try #require(
            ((assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []).first
        )
        let noteID = try #require(note.id?.uuidString)

        // The note was filed against the wrong child; move it to Etty.
        let output = try await tool(named: "update_observation", in: tools).handler([
            "note_id": .string(noteID),
            "student_names": .array([.string("Etty")])
        ])
        #expect(output.contains("Still linked to its presentation."))
        #expect(note.scope == .student(ettyID))
        #expect(note.lessonAssignment === assignment)
        // The lesson foreign key persistObservations writes alongside the
        // relationship is left alone too.
        #expect(note.lessonID == assignment.lessonID)

        // The presentation still counts as covered, since coverage follows the
        // relationship rather than the note's scope.
        let missing = try await tool(
            named: "presentations_missing_observations", in: tools
        ).handler([:])
        #expect(missing.contains("has a linked observation"))
    }
}
