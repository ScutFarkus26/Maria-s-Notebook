import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-12, agent MW: MCP write tools that recorded a classmate's
// finish on the wrong copy (#15), skipped the service that completes a
// check-in (#16) or a todo (#17), added a child to a plan without the repeat
// check (#18), put a check-in on a closed day (#19), journaled replies that
// changed nothing (#20), and three smaller ones (#22).

@Suite("MCP write tools (Fix1012MW)")
@MainActor
struct MCPToolsFix1012MWTests {
    private typealias Fixture = CheckInFixture

    private func call(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> String {
        try await Fixture.tool(named: name, in: tools).handler(arguments)
    }

    /// Whether one call, run as the request handler runs it, stayed out of
    /// the write journal.
    private func wroteNothing(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> Bool {
        let tool = try Fixture.tool(named: name, in: tools)
        return try await Fixture.outcome { try await tool.handler(arguments) }.wroteNothing
    }

    // MARK: - #15: completed_by on a linked copy

    @Test("completed_by naming a classmate on a linked copy is refused with her own copy's id")
    func completedByClassmateOnLinkedCopyIsRefused() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])
        let eli = try #require(rows["Eli"])

        let message = await Fixture.message {
            try await call("update_work", [
                "work_id": .string(try Fixture.id(of: maya)),
                "completed_by": .string("Eli")
            ], in: tools)
        }
        #expect(message.contains("[work id=\(try Fixture.id(of: eli))]"))
        #expect(message.contains("status"))
        #expect(context.safeFetch(CDFetchRequest(CDWorkCompletionRecord.self)).isEmpty)
        let eliID = try #require(WorkGrouping.owner(of: eli))
        #expect(maya.participant(for: eliID)?.completedAt == nil)
    }

    @Test("completed_by on a shared row still records that child's finish")
    func completedByOnSharedRowStillRecords() async throws {
        let (tools, context) = try Fixture.makeTools()
        let avigail = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avigail", lastName: "Green")
        let leshem = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leshem", lastName: "Pardes")
        let row = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Poster", studentID: try #require(avigail.id)
        )
        row.id = UUID()
        for student in [avigail, leshem] {
            let participant = CDWorkParticipantEntity(context: context)
            participant.id = UUID()
            participant.studentID = try #require(student.id).uuidString
            participant.work = row
        }
        #expect(CoreDataTestHelpers.save(context))

        let receipt = try await call("update_work", [
            "work_id": .string(try Fixture.id(of: row)),
            "completed_by": .string("Leshem")
        ], in: tools)
        #expect(receipt.contains("recorded Leshem Pardes as finished"))
        #expect(row.participant(for: try #require(leshem.id))?.completedAt != nil)
    }

    // MARK: - #16: complete_check_in_on through the service

    @Test("complete_check_in_on completes the work's linked todo, and the check-in keeps its day")
    func completeCheckInCompletesLinkedTodo() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let work = try #require(rows["Maya"])
        let todo = CDTodoItem(context: context)
        todo.title = "See Maya's checkerboard"
        todo.linkedWorkItemID = try Fixture.id(of: work)
        #expect(CoreDataTestHelpers.save(context))

        let receipt = try await call("update_work", [
            "work_id": .string(try Fixture.id(of: work)),
            "complete_check_in_on": .string("2026-09-18")
        ], in: tools)
        #expect(receipt.contains("completed the check-in on 2026-09-18"))
        #expect(todo.isCompleted)
        let checkIn = try #require(Fixture.checkIns(of: work, on: "2026-09-18", in: context).first)
        #expect(checkIn.status == .completed)
    }

    // MARK: - #17: resolve_follow_up and repeating todos

    @Test("resolve_follow_up completes a repeating todo and schedules its next occurrence")
    func resolveRepeatingTodoSchedulesNext() async throws {
        let (tools, context) = try Fixture.makeTools()
        let todo = CDTodoItem(context: context)
        todo.title = "Watch Etty D's reading"
        todo.recurrence = .weekly
        todo.dueDate = try CoreDataTestHelpers.day("2026-10-12")
        #expect(CoreDataTestHelpers.save(context))
        let todoID = try #require(todo.id)

        let receipt = try await call("resolve_follow_up", ["id": .string(todoID.uuidString)], in: tools)
        #expect(receipt.contains("Completed follow-up"))
        #expect(todo.isCompleted)
        let open = context.safeFetch(CDFetchRequest(CDTodoItem.self))
            .filter { !$0.isCompleted && $0.title == "Watch Etty D's reading" }
        #expect(open.count == 1)
        #expect(receipt.contains("next"))
    }

    // MARK: - #18: adding a child to a plan runs the repeat check

    private func seedPlanWithRepeat(
        in context: NSManagedObjectContext
    ) throws -> (plan: CDLessonAssignment, prior: CDLessonAssignment) {
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        let prior = PresentationFactory.makePresented(
            lesson: lesson, students: [ora],
            presentedAt: try CoreDataTestHelpers.day("2026-03-11"), context: context
        )
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: [etty], context: context)
        plan.schedule(onDay: try CoreDataTestHelpers.day("2026-09-16"))
        #expect(CoreDataTestHelpers.save(context))
        return (plan, prior)
    }

    @Test("update_presentation_roster refuses to add a child who already has the lesson, without purpose")
    func rosterAddRefusesARepeat() async throws {
        let (tools, context) = try Fixture.makeTools()
        let seeded = try seedPlanWithRepeat(in: context)
        let planID = try #require(seeded.plan.id).uuidString

        let message = await Fixture.message {
            try await call("update_presentation_roster", [
                "presentation_id": .string(planID),
                "add_students": .array([.string("Ora")])
            ], in: tools)
        }
        #expect(message.hasPrefix("update_presentation_roster refused — nothing has been changed."))
        #expect(message.contains("Ora Levi already has \"Checkerboard\" on record (2026-03-11)."))
        #expect(seeded.plan.studentIDs.count == 1)
    }

    @Test("update_presentation_roster adds a repeat once purpose says why, and notes it")
    func rosterAddWithPurposeNotesIt() async throws {
        let (tools, context) = try Fixture.makeTools()
        let seeded = try seedPlanWithRepeat(in: context)
        let planID = try #require(seeded.plan.id).uuidString

        let receipt = try await call("update_presentation_roster", [
            "presentation_id": .string(planID),
            "add_students": .array([.string("Ora")]),
            "purpose": .string("review")
        ], in: tools)
        #expect(receipt.contains("added Ora Levi"))
        #expect(seeded.plan.studentIDs.count == 2)
        #expect(MCPNotebookTools.RepeatPurpose.parse(notes: seeded.plan.notes) == .review)
    }

    // MARK: - #19: assign_work's check-in day

    @Test("assign_work's check-in on a closed day lands on the next school day and says so")
    func assignWorkCheckInSkipsClosedDay() async throws {
        let (tools, context) = try Fixture.makeTools()
        let service = SchoolCalendarService.shared
        service.invalidateCache()
        defer { service.invalidateCache() }
        CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Test")
        #expect(CoreDataTestHelpers.save(context))

        // 2026-09-26 is a Saturday.
        let receipt = try await call("assign_work", [
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Maya")]),
            "check_in_date": .string("2026-09-26")
        ], in: tools)
        let work = try #require(context.safeFetch(CDFetchRequest(CDWorkModel.self)).first)
        #expect(Fixture.checkIns(of: work, on: "2026-09-26", in: context).isEmpty)
        #expect(Fixture.checkIns(of: work, on: "2026-09-28", in: context).count == 1)
        #expect(receipt.contains("check-in 2026-09-28"))
        #expect(receipt.contains("2026-09-26 is not a school day"))
    }

    // MARK: - #20: replies that changed nothing stay out of the journal

    @Test("a create_observation batch of nothing but duplicates writes nothing")
    func duplicateObservationBatchWritesNothing() async throws {
        let (tools, context) = try Fixture.makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        #expect(CoreDataTestHelpers.save(context))
        let item: JSONValue = [
            "student_names": .array([.string("Maya")]),
            "body": .string("Built the trinomial cube twice."),
            "date": .string("2026-10-05")
        ]
        _ = try await call("create_observation", ["notes": .array([item])], in: tools)

        #expect(try await wroteNothing("create_observation", ["notes": .array([item])], in: tools))
    }

    @Test("resolve_follow_up on an already-completed todo or cleared flag writes nothing")
    func resolveAlreadyDoneWritesNothing() async throws {
        let (tools, context) = try Fixture.makeTools()
        let todo = CDTodoItem(context: context)
        todo.title = "Call Ora's father"
        todo.isCompleted = true
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Ora read aloud.")
        note.needsFollowUp = false
        #expect(CoreDataTestHelpers.save(context))

        #expect(try await wroteNothing(
            "resolve_follow_up", ["id": .string(try #require(todo.id).uuidString)], in: tools
        ))
        #expect(try await wroteNothing(
            "resolve_follow_up", ["id": .string(try #require(note.id).uuidString)], in: tools
        ))
    }

    @Test("skip_year_plan_entries and clear_year_plan with nothing to do write nothing")
    func yearPlanNoOpsWriteNothing() async throws {
        let (tools, context) = try Fixture.makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        #expect(CoreDataTestHelpers.save(context))

        #expect(try await wroteNothing("skip_year_plan_entries", ["student_name": .string("Maya")], in: tools))
        #expect(try await wroteNothing(
            "clear_year_plan", ["student_name": .string("Maya"), "confirm": .bool(true)], in: tools
        ))
    }

    // MARK: - #21: practice_sessions says how to reach further back

    @Test("practice_sessions points to days_back, not limit, for older sessions")
    func practiceSessionsDescriptionNamesDaysBack() throws {
        let (tools, _) = try Fixture.makeTools()
        let description = try Fixture.tool(named: "practice_sessions", in: tools).description
        #expect(description.contains("days_back"))
        #expect(!description.contains("raise limit"))
    }

    // MARK: - #22: the smaller ones

    @Test("create_observation with one child named twice files a one-child note")
    func observationMergesARepeatedName() async throws {
        let (tools, context) = try Fixture.makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        #expect(CoreDataTestHelpers.save(context))

        _ = try await call("create_observation", [
            "student_names": .array([.string("Maya"), .string("Maya Stern")]),
            "body": .string("Chose the pin map on her own.")
        ], in: tools)
        let note = try #require(context.safeFetch(CDFetchRequest(CDNote.self)).first)
        #expect(note.scope == .student(try #require(maya.id)))
    }

    @Test("add_follow_up merges a repeated name and takes a student id")
    func followUpMergesNamesAndTakesIDs() async throws {
        let (tools, context) = try Fixture.makeTools()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dahan")
        #expect(CoreDataTestHelpers.save(context))
        let ettyID = try #require(etty.id).uuidString

        _ = try await call("add_follow_up", [
            "title": .string("Hear Etty read"),
            "student_names": .array([.string(ettyID), .string("Etty Klein")])
        ], in: tools)
        let todo = try #require(context.safeFetch(CDFetchRequest(CDTodoItem.self)).first)
        #expect(todo.studentIDsArray == [ettyID])
    }

    @Test("schedule_meeting refuses a child who has left")
    func scheduleMeetingRefusesDepartedChild() async throws {
        let (tools, context) = try Fixture.makeTools()
        CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rivka", lastName: "Stein", enrollmentStatus: .transferred
        )
        #expect(CoreDataTestHelpers.save(context))

        let message = await Fixture.message {
            try await call("schedule_meeting", [
                "student": .string("Rivka"), "date": .string("2026-10-14")
            ], in: tools)
        }
        #expect(message.contains("Rivka Stein"))
        #expect(context.safeFetch(CDFetchRequest(CDScheduledMeeting.self)).isEmpty)
    }
}
