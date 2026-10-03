import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Logic-break sweep 2026-09-29, Group D. MCP writes that half-committed or
// reported success on failure: a completion saved before a later argument
// was refused, partial edits left pending in the shared context, save results
// ignored, `until`-only windows that ended before they began, a reschedule
// onto a closed day, a plan that never answered its year-plan entry,
// previews journaled as writes, and a failed backup that read as success.
@Suite("MCP write safety")
@MainActor
struct MCPWriteSafetyTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func daysAgo(_ days: Int) -> Date {
        AppCalendar.shared.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    private func dayText(_ days: Int) -> JSONValue {
        .string(MCPNotebookTools.isoDay.string(from: daysAgo(days)))
    }

    /// A row missing a mandatory value, so the context's next save fails.
    private func poisonNextSave(_ context: NSManagedObjectContext) {
        let broken = CDLessonAssignment(context: context)
        broken.setValue(nil, forKey: "lessonID")
    }

    // MARK: - D12 / D13: a refused argument leaves nothing behind

    @Test("update_work: a refused status rolls back the completion recorded before it")
    func updateWorkCompletionRollsBack() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame", area: "Math", sequence: "Operations")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        CoreDataTestHelpers.save(context)
        _ = try await tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Bead Frame"), "student_names": .array([.string("Sam")])
        ])
        let workID = try #require(context.safeFetch(CDFetchRequest(CDWorkModel.self)).first?.id)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_work", in: tools).handler([
                "work_id": .string(workID.uuidString),
                "completed_by": .string("Sam"),
                "status": .string("bogus")
            ])
        }

        #expect(context.safeFetch(CDFetchRequest(CDWorkCompletionRecord.self)).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test("mark_attendance: a refused absence reason leaves no mark behind")
    func markAttendanceRollsBack() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .leadGuide)
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Nina", lastName: "Barr")
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "mark_attendance", in: tools).handler([
                "student_name": .string("Nina"),
                "status": .string("present"),
                "absence_reason": .string(AbsenceReason.allCases[0].rawValue)
            ])
        }

        #expect(!context.hasChanges)
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).isEmpty)
    }

    @Test("update_todo: a refused priority leaves the new title unsaved and undone")
    func updateTodoRollsBack() async throws {
        let (tools, context) = try makeTools()
        let todo = CDTodoItem(context: context)
        todo.id = UUID()
        todo.title = "Order more bead bars"
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_todo", in: tools).handler([
                "todo_id": .string(try #require(todo.id).uuidString),
                "title": .string("Order golden beads"),
                "priority": .string("whenever")
            ])
        }

        #expect(todo.title == "Order more bead bars")
        #expect(!context.hasChanges)
    }

    // MARK: - D14: a failed save is a failure

    @Test("mark_mastered: a failed save is an error and marks nothing")
    func markMasteredChecksItsSave() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Mult")
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Pardo")
        let given = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ada], scheduledFor: daysAgo(3), context: context
        )
        _ = try LifecycleService.recordPresentation(from: given, presentedAt: daysAgo(3), modelContext: context)
        CoreDataTestHelpers.save(context)
        poisonNextSave(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "mark_mastered", in: tools).handler([
                "lesson": .string("Checkerboard"), "student_names": .array([.string("Ada")])
            ])
        }

        let rows = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        #expect(rows.allSatisfy { $0.state != .proficient })
        #expect(!context.hasChanges)
    }

    @Test("RolloverService.apply: a failed save throws and changes nobody")
    func rolloverChecksItsSave() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Baila", lastName: "G", level: .upper)
        CoreDataTestHelpers.save(context)
        var plan = RolloverPlan(effectiveDate: Date(), writeNotes: false)
        plan.outcomes[try #require(student.id)] = .promote(to: .adolescent)
        poisonNextSave(context)

        #expect(throws: RolloverService.ApplyError.self) {
            try RolloverService.apply(plan, students: [student], incomingYearLabel: "2026–2027", context: context)
        }
        #expect(student.level == .upper)
        #expect(!context.hasChanges)
    }

    // MARK: - D15: an until-only window ends on until

    @Test("student_observations: until alone reads the days_back days ending there")
    func observationsUntilOnly() async throws {
        let (tools, context) = try makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.save(context)
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Map work, seventy days back.")
        note.createdAt = daysAgo(70)
        note.scope = .student(try #require(ora.id))
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "student_observations", in: tools).handler([
            "student_name": .string("Ora"), "until": dayText(60)
        ])

        #expect(output.contains("Map work, seventy days back."))
        #expect(output.contains("in the 30 days through"))
    }

    @Test("practice_sessions: until alone reads the days_back days ending there")
    func practiceUntilOnly() async throws {
        let (tools, context) = try makeTools()
        let ana = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "Perez")
        CoreDataTestHelpers.save(context)
        let session = CDPracticeSession(context: context)
        session.id = UUID()
        session.date = daysAgo(400)
        session.studentIDsArray = [try #require(ana.id).uuidString]
        session.sharedNotes = "Bead frame, four hundred days back."
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "practice_sessions", in: tools).handler([
            "student_name": .string("Ana"), "until": dayText(380)
        ])

        #expect(output.contains("Bead frame, four hundred days back."))
    }

    // MARK: - D17: scheduling

    @Test("reschedule_presentation refuses a day school is out")
    func rescheduleRefusesClosedDay() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math", sequence: "Ops")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: [maya], context: context)
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "reschedule_presentation", in: tools).handler([
                "presentation_id": .string(try #require(plan.id).uuidString),
                "date": .string("2026-09-12")  // a Saturday
            ])
        }
        #expect(plan.scheduledFor == nil)
    }

    @Test("schedule_presentation promotes the child's planned year-plan entry into the plan")
    func schedulePromotesEntry() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math", sequence: "Ops")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(maya.id).uuidString
        entry.lessonID = try #require(lesson.id).uuidString
        entry.plannedDate = Date().addingTimeInterval(10 * 86_400)
        entry.sequenceGroupKey = "Math::Ops"
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "schedule_presentation", in: tools).handler([
            "lesson": .string("Stamp Game"),
            "student_names": .array([.string("Maya")]),
            "date": .string("2026-09-14")  // a Monday
        ])

        let plan = try #require(context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).first)
        #expect(entry.isPromoted)
        #expect(entry.promotedAssignmentID == plan.id?.uuidString)
        #expect(receipt.contains("promoted into it"))
    }

    // MARK: - D18: the journal and create_backup

    private actor WriteCollector {
        private(set) var records: [MCPWriteRecord] = []
        func add(_ record: MCPWriteRecord) { records.append(record) }
    }

    @Test("A preview and a no-op are not journaled; the confirmed write is")
    func previewsAreNotJournaled() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math", sequence: "Ops")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: [maya], context: context)
        CoreDataTestHelpers.save(context)
        let id = try #require(plan.id).uuidString

        let collector = WriteCollector()
        let handler = MCPRequestHandler(
            serverVersion: "1.0-test", tools: tools, onWrite: { await collector.add($0) }
        )
        func call(_ name: String, _ arguments: [String: Any]) async throws {
            let body: [String: Any] = [
                "jsonrpc": "2.0", "id": 1, "method": "tools/call",
                "params": ["name": name, "arguments": arguments]
            ]
            _ = await handler.handle(line: try JSONSerialization.data(withJSONObject: body))
        }

        try await call("discard_presentation", ["presentation_id": id])
        try await call("update_presentation_roster", ["presentation_id": id, "add_students": ["Maya"]])
        #expect(await collector.records.isEmpty)

        try await call("discard_presentation", ["presentation_id": id, "confirm": true])
        #expect(await collector.records.map(\.tool) == ["discard_presentation"])
    }

    @Test("create_backup: a failed backup is a tool error")
    func failedBackupIsAnError() {
        struct DiskFull: Error {}
        #expect(throws: MCPToolError.self) {
            _ = try MCPNotebookTools.backupReceipt(.failure(Date(), DiskFull()))
        }
    }

    @Test("create_backup: a failure tells Claude the plain sentence and the technical detail")
    func failedBackupCarriesDetailForClaude() throws {
        let cause = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError,
                            userInfo: [NSLocalizedDescriptionKey: "The disk is full."])
        let failure = BackupWriter.WriterError.photoUnreadable(filename: "note-photo.heic", underlying: cause)
        let error = try #require(throws: MCPToolError.self) {
            _ = try MCPNotebookTools.backupReceipt(.failure(Date(), failure))
        }
        // The app's plain sentence leads, so Claude can relay it to Danny as is.
        #expect(error.message.hasPrefix("The backup could not be written: \(failure.localizedDescription)"))
        // Then what only Claude needs: the case, its values and the system cause.
        #expect(error.message.contains("\nDetails: "))
        #expect(error.message.contains("photoUnreadable"))
        #expect(error.message.contains("note-photo.heic"))
        #expect(error.message.contains("NSCocoaErrorDomain"))
        #expect(error.message.contains("640"))
    }
}
