import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11, review (b) of the MCP and chat write fixes: Ask AI's
// meeting and follow-up writes left a failed write pending, a huge count
// still crashed adjust_supply, a failed mastery batch said "nothing was
// marked" after a finished track had saved the first mark, and notes filed
// by record_presentation or unflagged by resolve_follow_up went unannounced.

/// A half-made row from some open screen that can't be saved yet, so the
/// context's next save fails, as it does when the guide is mid-edit.
@MainActor
@discardableResult
private func unsavableRow(in context: NSManagedObjectContext) -> CDLessonAssignment {
    let broken = CDLessonAssignment(context: context)
    broken.setValue(nil, forKey: "lessonID")
    return broken
}

@MainActor
private func call(
    _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
) async throws -> String {
    let tool = try #require(tools.first { $0.name == name })
    return try await tool.handler(arguments)
}

// MARK: - Ask AI's write tools undo a failed write

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)

@Suite("Chat writes undo a failed save (Fix1011ReviewB1)")
@MainActor
struct ChatWritesUndoFix1011ReviewB1Tests {
    @Test("A failed recordStudentMeeting takes back its meeting, goals and booking, not the guide's edits")
    func failedChatMeetingKeepsGuideEdits() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        let booking = CDScheduledMeeting(context: context)
        booking.studentID = try #require(maya.id).uuidString
        booking.date = AppCalendar.startOfDay(Date())
        CoreDataTestHelpers.save(context)

        maya.nickname = "Mimi"
        let pending = unsavableRow(in: context)

        let tool = RecordStudentMeetingTool(contextProvider: { context })
        let output = try await tool.call(arguments: .init(
            student: "Maya", date: "", reflection: "Chose long division on paper.",
            lessonRequests: "", guideNotes: "", goals: ["Finish the checkerboard"]
        ))

        #expect(output.contains("could not be saved"))
        #expect(!context.insertedObjects.contains { $0 is CDStudentMeeting })
        #expect(!context.insertedObjects.contains { $0 is CDStudentFocusItem })
        #expect(!booking.isDeleted)
        #expect(!context.deletedObjects.contains(booking))
        #expect(maya.nickname == "Mimi")
        #expect(context.insertedObjects.contains(pending))
    }

    @Test("A failed addFollowUp leaves no todo pending")
    func failedChatFollowUpLeavesNothing() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Katz")
        CoreDataTestHelpers.save(context)
        let pending = unsavableRow(in: context)

        let tool = AddFollowUpTool(contextProvider: { context })
        let output = try await tool.call(arguments: .init(
            title: "Order Ellis Island books", notes: "", studentNames: ["Etty"], dueDate: ""
        ))

        #expect(output.contains("could not be saved"))
        #expect(!context.insertedObjects.contains { $0 is CDTodoItem })
        #expect(context.insertedObjects.contains(pending))
    }

    @Test("A failed resolveFollowUp leaves the todo open")
    func failedChatResolveLeavesTodoOpen() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let todo = CDTodoItem(context: context)
        todo.title = "Call Etty's mother"
        let todoID = try #require(todo.id)
        CoreDataTestHelpers.save(context)
        unsavableRow(in: context)

        let tool = ResolveFollowUpTool(contextProvider: { context })
        let output = try await tool.call(arguments: .init(id: todoID.uuidString))

        #expect(output.contains("could not be saved"))
        #expect(!todo.isCompleted)
        #expect(todo.completedAt == nil)
    }
}

#endif

// MARK: - adjust_supply refuses a count too big to add up

// A separate suite: before the fix this one stops the test run (the sum
// overflows and the app traps).
@Suite("adjust_supply with huge numbers (Fix1011ReviewB1)")
@MainActor
struct SupplyHugeNumberFix1011ReviewB1Tests {
    private func seedPencils(in context: NSManagedObjectContext) -> CDSupply {
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = "Pencils"
        supply.currentQuantity = 40
        supply.createdAt = Date()
        #expect(CoreDataTestHelpers.save(context))
        return supply
    }

    @Test("A change or count far too big is refused, and the count is left alone")
    func hugeNumbersAreRefused() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        let pencils = seedPencils(in: context)

        for arguments: [String: JSONValue] in [
            ["supply": .string("Pencils"), "change": .int(Int.max)],
            ["supply": .string("Pencils"), "change": .int(Int.min)],
            ["supply": .string("Pencils"), "change": .int(5_000_000)],
            ["supply": .string("Pencils"), "set_to": .int(Int.min)],
            ["supply": .string("Pencils"), "set_to": .int(Int.max)],
            ["supply": .string("Pencils"), "set_to": .int(5_000_000)]
        ] {
            await #expect(throws: MCPToolError.self) {
                _ = try await call("adjust_supply", arguments, in: tools)
            }
        }
        #expect(pencils.currentQuantity == 40)
        #expect(!context.hasChanges)

        let ordinary = try await call(
            "adjust_supply", ["supply": .string("Pencils"), "change": .int(-12)], in: tools
        )
        #expect(ordinary.contains("now 28"))
    }
}

// MARK: - mark_mastered says what a partial save kept

@Suite("mark_mastered after a save part-way through (Fix1011ReviewB1)")
@MainActor
struct MasteryPartialSaveFix1011ReviewB1Tests {
    /// Avital, presented two lessons: one that alone makes up a track she is
    /// enrolled in, and one off any track.
    private func seedLessons(in context: NSManagedObjectContext) throws -> (commutative: CDLesson, bells: CDLesson) {
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Beyderman")
        let avitalID = try #require(avital.id).uuidString
        // A one-lesson track Avital is enrolled in: marking its lesson
        // finishes the track, and the track check saves.
        let commutative = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Commutative Law", area: "Math", sequence: "Laws"
        )
        let track = try SequenceTrackService.getOrCreateTrack(area: "Math", sequence: "Laws", context: context)
        let enrollment = CDStudentTrackEnrollmentEntity(context: context)
        enrollment.studentID = avitalID
        enrollment.trackID = try #require(track.id).uuidString
        enrollment.track = track
        enrollment.isActive = true
        let bells = CoreDataTestHelpers.seedLesson(in: context, name: "Bells", area: "Music", sequence: "Bells")
        for lesson in [commutative, bells] {
            let row = CDLessonPresentation(context: context)
            row.studentID = avitalID
            row.lessonID = try #require(lesson.id).uuidString
            row.state = .presented
            row.presentedAt = Date()
        }
        #expect(CoreDataTestHelpers.save(context))
        return (commutative, bells)
    }

    @Test("When a finished track saves the first mark and the final save fails, the reply says what was kept")
    func partialSaveIsReported() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        let (commutative, bells) = try seedLessons(in: context)

        // After that inner save, something leaves the context unsavable, so
        // the batch's own save fails.
        let saved = NotificationCenter.default.addObserver(
            forName: NSManagedObjectContext.didSaveObjectsNotification, object: context, queue: nil
        ) { _ in
            MainActor.assumeIsolated { _ = unsavableRow(in: context) }
        }
        defer { NotificationCenter.default.removeObserver(saved) }

        var message = ""
        do {
            _ = try await call("mark_mastered", [
                "marks": .array([
                    .object(["lesson": .string("The Commutative Law"), "student_names": .array([.string("Avital")])]),
                    .object(["lesson": .string("Bells"), "student_names": .array([.string("Avital")])])
                ])
            ], in: tools)
            Issue.record("Expected the batch's save to fail")
        } catch let error as MCPToolError {
            message = error.message
        }

        // What is on disk: the first mark and the finished track, not the second.
        let disk = stack.container.newBackgroundContext()
        let onDisk: [String: String] = disk.performAndWait {
            Dictionary(uniqueKeysWithValues: disk.safeFetch(CDFetchRequest(CDLessonPresentation.self)).map {
                ($0.lessonID, $0.state.rawValue)
            })
        }
        #expect(onDisk[try #require(commutative.id).uuidString] == LessonPresentationState.proficient.rawValue)
        #expect(onDisk[try #require(bells.id).uuidString] != LessonPresentationState.proficient.rawValue)

        // The reply says so, rather than "nothing was marked".
        #expect(!message.contains("nothing was marked"))
        #expect(message.contains("The Commutative Law"))
        #expect(message.contains("Bells"))
    }
}

// MARK: - Notes filed or unflagged over MCP are announced

@Suite("MCP note writes announce the note (Fix1011ReviewB1)")
@MainActor
struct NoteAnnouncementFix1011ReviewB1Tests {
    @Test("record_presentation announces the observations it filed")
    func recordPresentationAnnounces() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        CoreDataTestHelpers.seedLesson(in: context, name: "Racks and Tubes", area: "Math", sequence: "Division")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let announced = NoteDidSaveRecorder()
        defer { announced.stop() }

        _ = try await call("record_presentation", [
            "lesson": .string("Racks and Tubes"),
            "student_names": .array([.string("Ora")]),
            "group_observation": .string("Followed the exchange without prompting.")
        ], in: tools)

        let noteIDs = Set(context.safeFetch(CDFetchRequest(CDNote.self)).compactMap(\.id))
        #expect(noteIDs.count == 1)
        #expect(announced.ids.contains { noteIDs.contains($0) })
    }

    @Test("resolve_follow_up announces the note whose flag it cleared")
    func resolveFlagAnnounces() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let note = CDNote(context: context)
        note.body = "Lost the place when borrowing."
        note.scope = .student(try #require(ora.id))
        note.needsFollowUp = true
        let noteID = try #require(note.id)
        CoreDataTestHelpers.save(context)
        let announced = NoteDidSaveRecorder()
        defer { announced.stop() }

        _ = try await call("resolve_follow_up", ["id": .string(noteID.uuidString)], in: tools)

        #expect(!note.needsFollowUp)
        #expect(announced.ids.contains(noteID))
    }
}
