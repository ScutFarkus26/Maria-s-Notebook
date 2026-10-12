import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11, agent M: MCP writes that failed took the guide's own
// unsaved edits with them (#53), notes filed over MCP that the note lists
// never heard about (#48), "Maya S" not found (#49), departed children's
// follow-ups (#51), and a meeting recorded for a day still to come (#53).

@Suite("MCP writes and lookups (Fix1011M)")
@MainActor
struct MCPToolsFix1011MTests {
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

    /// A half-made row from some open screen that can't be saved yet, so the
    /// context's next save fails, as it does when the guide is mid-edit.
    @discardableResult
    private func unsavableRow(in context: NSManagedObjectContext) -> CDLessonAssignment {
        let broken = CDLessonAssignment(context: context)
        broken.setValue(nil, forKey: "lessonID")
        return broken
    }

    // MARK: - #53: a failed write undoes only its own changes

    @Test("A failed create_observation keeps the guide's own unsaved edits")
    func failedObservationKeepsGuideEdits() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        CoreDataTestHelpers.save(context)

        // The guide's unsaved work in the app: a nickname typed on Maya's page,
        // and a row another screen hasn't finished.
        maya.nickname = "Mimi"
        let pending = unsavableRow(in: context)

        await #expect(throws: MCPToolError.self) {
            _ = try await call("create_observation", [
                "student_names": .array([.string("Maya")]),
                "body": .string("Built the trinomial cube twice.")
            ], in: tools)
        }

        #expect(!context.insertedObjects.contains { $0 is CDNote })
        #expect(maya.nickname == "Mimi")
        #expect(context.insertedObjects.contains(pending))
    }

    @Test("A refused update_work takes back its own completion, not the guide's edits")
    func refusedUpdateWorkKeepsGuideEdits() async throws {
        let (tools, context) = try makeTools()
        let sam = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        let ana = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "Perez")
        // A row the two share, where completed_by records one child's finish.
        let row = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bead Frame", studentID: try #require(sam.id))
        row.id = UUID()
        for student in [sam, ana] {
            let participant = CDWorkParticipantEntity(context: context)
            participant.id = UUID()
            participant.studentID = try #require(student.id).uuidString
            participant.work = row
        }
        CoreDataTestHelpers.save(context)
        let workID = try #require(row.id)

        sam.nickname = "Sammy"

        await #expect(throws: MCPToolError.self) {
            _ = try await call("update_work", [
                "work_id": .string(workID.uuidString),
                "completed_by": .string("Sam"),
                "status": .string("bogus")
            ], in: tools)
        }

        #expect(!context.insertedObjects.contains { $0 is CDWorkCompletionRecord })
        #expect(sam.nickname == "Sammy")
        #expect(sam.hasChanges)
    }

    @Test("remove_student_from_work, whose service undoes its own changes, leaves the guide's edits too")
    func failedRemovalKeepsGuideEdits() async throws {
        let (tools, context) = try makeTools()
        let avigail = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avigail", lastName: "Greenbaum")
        let leshem = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leshem", lastName: "Pardes")
        let lessonID = UUID()
        let avigailsRow = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Poster", studentID: try #require(avigail.id), lessonID: lessonID
        )
        let leshemsRow = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Poster", studentID: try #require(leshem.id), lessonID: lessonID
        )
        for row in [avigailsRow, leshemsRow] {
            for student in [avigail, leshem] {
                let participant = CDWorkParticipantEntity(context: context)
                participant.studentID = student.id?.uuidString ?? ""
                participant.work = row
            }
        }
        CoreDataTestHelpers.save(context)

        avigail.nickname = "Avi"
        let pending = unsavableRow(in: context)

        await #expect(throws: MCPToolError.self) {
            _ = try await call("remove_student_from_work", [
                "work_id": .string(try #require(avigailsRow.id?.uuidString)),
                "student_name": .string("Leshem"),
                "confirm": .bool(true)
            ], in: tools)
        }

        #expect(!leshemsRow.isDeleted)
        #expect(avigailsRow.participant(for: try #require(leshem.id)) != nil)
        #expect(avigail.nickname == "Avi")
        #expect(context.insertedObjects.contains(pending))
    }

    @Test("A save inside a write is kept; a later failure undoes only what came after it")
    func scopeKeepsAMidWriteSave() throws {
        let (_, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        CoreDataTestHelpers.save(context)

        let scope = MCPWriteScope(context: context)
        maya.nickname = "Mimi"
        #expect(context.safeSave())
        maya.level = .upper
        scope.undo()

        #expect(maya.nickname == "Mimi")
        #expect(maya.level == .lower)
        #expect(!maya.hasChanges)
    }

    @Test("A write that finishes keeps everything it changed")
    func scopeCommitKeepsChanges() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        CoreDataTestHelpers.save(context)
        let guideUndoManager = UndoManager()
        context.undoManager = guideUndoManager

        _ = try await call("create_observation", [
            "student_names": .array([.string("Maya")]),
            "body": .string("Chose the long chain.")
        ], in: tools)

        #expect(!context.hasChanges)
        #expect(context.safeFetch(CDFetchRequest(CDNote.self)).count == 1)
        // The context gets its own undo manager back, with nothing of the write's on it.
        #expect(context.undoManager === guideUndoManager)
        #expect(!guideUndoManager.canUndo)
    }

    // MARK: - #48: notes filed over MCP are announced

    @Test("create_observation and update_observation announce the note they saved")
    func observationWritesAnnounceTheNote() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        CoreDataTestHelpers.save(context)
        let announced = NoteDidSaveRecorder()
        defer { announced.stop() }

        _ = try await call("create_observation", [
            "student_names": .array([.string("Maya")]),
            "body": .string("Built the trinomial cube twice.")
        ], in: tools)
        let note = try #require(context.safeFetch(CDFetchRequest(CDNote.self)).first)
        let noteID = try #require(note.id)
        #expect(announced.ids.contains(noteID))

        let before = announced.ids.filter { $0 == noteID }.count
        _ = try await call("update_observation", [
            "note_id": .string(noteID.uuidString),
            "body": .string("Built the trinomial cube three times.")
        ], in: tools)
        #expect(announced.ids.filter { $0 == noteID }.count > before)
    }

    @Test("A batch of observations is announced too")
    func observationBatchAnnounces() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "Gold")
        CoreDataTestHelpers.save(context)
        let announced = NoteDidSaveRecorder()
        defer { announced.stop() }

        _ = try await call("create_observation", [
            "notes": .array([
                .object(["student_names": .array([.string("Maya")]), "body": .string("Chose the map.")]),
                .object(["student_names": .array([.string("Noa")]), "body": .string("Chose the cube.")])
            ])
        ], in: tools)
        let noteIDs = Set(context.safeFetch(CDFetchRequest(CDNote.self)).compactMap(\.id))
        #expect(noteIDs.count == 2)
        #expect(announced.ids.contains { noteIDs.contains($0) })
    }

    // MARK: - #49: the short name finds her

    @Test("\"Maya S\" finds Maya Stern when two children are called Maya")
    func shortNameResolves() throws {
        let (_, context) = try makeTools()
        let stern = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Tal")
        CoreDataTestHelpers.save(context)

        #expect(try MCPNotebookTools.resolveStudent(named: "Maya S", in: context) == stern)
        #expect(try MCPNotebookTools.resolveStudent(named: "maya s", in: context) == stern)
    }

    @Test("Two children with one first name: the reply offers each short name")
    func ambiguityOffersShortNames() throws {
        let (_, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Davis")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Katz")
        CoreDataTestHelpers.save(context)

        do {
            _ = try MCPNotebookTools.resolveStudent(named: "Etty", in: context)
            Issue.record("Expected an ambiguity error")
        } catch let error as MCPToolError {
            #expect(error.message.contains("Etty Davis (Etty D)"))
            #expect(error.message.contains("Etty Katz (Etty K)"))
        }
    }

    // MARK: - #51: follow-ups for children still here

    @Test("list_open_follow_ups leaves out a child who left, unless she is named")
    func followUpsLeaveOutDepartedChildren() async throws {
        let (tools, context) = try makeTools()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Here")
        let bea = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Bea", lastName: "Gone", enrollmentStatus: .withdrawn
        )
        for (student, text) in [(ada, "Ada's goal: long division"), (bea, "Bea's goal: cursive")] {
            FocusItemService.create(
                studentID: try #require(student.id), text: text, meetingID: UUID(), sortOrder: 0, context: context
            )
            let note = CDNote(context: context)
            note.body = "Flagged about \(student.firstName)"
            note.scope = .student(try #require(student.id))
            note.needsFollowUp = true
        }
        CoreDataTestHelpers.save(context)

        let everyone = try await call("list_open_follow_ups", [:], in: tools)
        #expect(everyone.contains("Ada's goal: long division"))
        #expect(everyone.contains("Flagged about Ada"))
        #expect(!everyone.contains("Bea's goal: cursive"))
        #expect(!everyone.contains("Flagged about Bea"))

        let hers = try await call("list_open_follow_ups", ["student_name": .string("Bea")], in: tools)
        #expect(hers.contains("Bea's goal: cursive"))
        #expect(hers.contains("Flagged about Bea"))
    }

    // MARK: - #53: a meeting can't be recorded before it happens

    @Test("create_meeting_entry refuses a day still to come")
    func meetingEntryRefusesFutureDay() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Katz")
        CoreDataTestHelpers.save(context)
        let nextWeek = AppCalendar.addingDays(7, to: AppCalendar.startOfDay(Date()))

        await #expect(throws: MCPToolError.self) {
            _ = try await call("create_meeting_entry", [
                "student": .string("Etty"),
                "date": .string(MCPNotebookTools.isoDay.string(from: nextWeek)),
                "reflection": .string("Planned the week.")
            ], in: tools)
        }
        #expect(context.safeFetch(CDFetchRequest(CDStudentMeeting.self)).isEmpty)
    }
}

// A separate suite: before the fix this one stops the test run (the app
// traps converting a number too big for Int).
@Suite("MCP number arguments (Fix1011M)")
struct MCPNumberArgumentsFix1011MTests {
    @Test("A number too big for a whole number reads as missing, not a crash")
    func hugeNumberReadsAsMissing() {
        #expect(JSONValue.double(1e20).intValue == nil)
        #expect(JSONValue.double(-1e20).intValue == nil)
        #expect(JSONValue.double(.infinity).intValue == nil)
        #expect(JSONValue.double(.nan).intValue == nil)
        #expect(JSONValue.double(2.5).intValue == nil)
        #expect(JSONValue.double(12).intValue == 12)
    }

    @Test("A huge limit falls back to the default")
    @MainActor
    func hugeLimitUsesDefault() {
        let value = MCPNotebookTools.intArgument(["limit": .double(1e20)], "limit", default: 10, range: 1...50)
        #expect(value == 10)
    }
}
