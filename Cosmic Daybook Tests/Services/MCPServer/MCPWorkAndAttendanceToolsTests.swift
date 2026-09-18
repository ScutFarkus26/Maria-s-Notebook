import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Work And Attendance Tools")
@MainActor
struct MCPWorkAndAttendanceToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func workItems(in context: NSManagedObjectContext) -> [CDWorkModel] {
        context.safeFetch(CDFetchRequest(CDWorkModel.self))
    }

    // MARK: - assign_work

    @Test("assign_work creates one item per student and cross-links them")
    func assignWorkLinksParticipants() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Volcano Study", area: "Science", sequence: "Geology")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Ross")
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Volcano Study"),
            "student_names": .array([.string("Maya"), .string("Eli")]),
            "title": .string("Volcano research"),
            "due_date": .string("2026-09-25")
        ])
        #expect(receipt.contains("Volcano research"))

        let items = workItems(in: context)
        #expect(items.count == 2)
        // createWork adds the owner as a participant and the cross-link adds the
        // other child, so each item resolves to the whole pair — that is what
        // makes the group read as one piece of work everywhere in the app.
        for item in items {
            #expect(MCPNotebookTools.workStudentIDs(for: item).count == 2)
        }
    }

    @Test("student_work lists open work and its due date")
    func studentWorkListsOpenWork() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Map Work", area: "Geography", sequence: "Continents")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "Perez")
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Map Work"),
            "student_names": .array([.string("Ana")]),
            "title": .string("Continent map")
        ])

        let output = try await tool(named: "student_work", in: tools).handler([
            "student_name": .string("Ana")
        ])
        #expect(output.contains("Open work for Ana Perez"))
        #expect(output.contains("Continent map"))
    }

    // MARK: - update_work

    @Test("update_work folds the legacy status + outcome pair into one status")
    func updateWorkCompletesWithOutcome() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Fraction Circles", area: "Math", sequence: "Fractions")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Fraction Circles"),
            "student_names": .array([.string("Sam")])
        ])
        let work = try #require(workItems(in: context).first)
        let id = try #require(work.id).uuidString

        let receipt = try await tool(named: "update_work", in: tools).handler([
            "work_id": .string(id),
            "status": .string("complete"),
            "outcome": .string("mastered")
        ])
        #expect(receipt.contains("logged as Mastered"))
        #expect(work.status == .mastered)
        #expect(work.completedAt != nil)
    }

    @Test("update_work refuses an empty change")
    func updateWorkRefusesEmptyChange() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Grammar Boxes", area: "Language", sequence: "Grammar")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Rae", lastName: "Kim")
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Grammar Boxes"),
            "student_names": .array([.string("Rae")])
        ])
        let id = try #require(workItems(in: context).first?.id).uuidString

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_work", in: tools).handler(["work_id": .string(id)])
        }
    }

    // MARK: - mark_attendance

    @Test("mark_attendance records a status the day view then reports")
    func markAttendanceRecordsStatus() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .leadGuide)
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Nina", lastName: "Barr")
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "mark_attendance", in: tools).handler([
            "student_name": .string("Nina"),
            "status": .string("absent"),
            "date": .string("2026-09-14"),
            "absence_reason": .string("sick")
        ])
        #expect(receipt.contains("absent"))

        let day = try await tool(named: "attendance_for_day", in: tools).handler([
            "date": .string("2026-09-14")
        ])
        #expect(day.contains("Absent (1): Nina Barr"))
    }

    @Test("mark_attendance refuses an absence reason on a present mark")
    func markAttendanceRefusesReasonWhenPresent() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .leadGuide)
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Omar", lastName: "Diaz")
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "mark_attendance", in: tools).handler([
                "student_name": .string("Omar"),
                "status": .string("present"),
                "absence_reason": .string("sick")
            ])
        }
    }

    @Test("student_attendance tallies the days a child was away")
    func studentAttendanceTallies() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .leadGuide)
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Lila", lastName: "Nakai")
        CoreDataTestHelpers.save(context)

        let markTool = try tool(named: "mark_attendance", in: tools)
        let today = MCPNotebookTools.isoDay.string(from: Date())
        _ = try await markTool.handler([
            "student_name": .string("Lila"),
            "status": .string("tardy"),
            "date": .string(today)
        ])

        let output = try await tool(named: "student_attendance", in: tools).handler([
            "student_name": .string("Lila")
        ])
        #expect(output.contains("1 tardy"))
        #expect(output.contains("Days away or late:"))
    }

    // MARK: - update_work: one status, per child

    @Test("update_work with a closing status settles the row's check-ins")
    func updateWorkClosingStatusSettlesCheckIns() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame", area: "Math", sequence: "Operations")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        CoreDataTestHelpers.save(context)
        _ = try await tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Bead Frame"),
            "student_names": .array([.string("Sam")])
        ])
        let work = try #require(workItems(in: context).first)
        let today = AppCalendar.startOfDay(Date())
        let todays = CDWorkCheckIn.make(for: work, on: today, purpose: "progressCheck", in: context)
        let later = CDWorkCheckIn.make(for: work, on: AppCalendar.addingDays(7, to: today), in: context)
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "update_work", in: tools).handler([
            "work_id": .string(try #require(work.id).uuidString),
            "status": .string("keepPracticing"),
            "note": .string("Needs the trinomial cube again")
        ])

        #expect(receipt.contains("logged as Keep Practicing"))
        #expect(work.status == .keepPracticing)
        #expect(work.completedAt != nil)
        #expect(todays.status == .completed)
        #expect(later.status == .skipped)
    }

    @Test("update_work with students logs only those children's linked copies")
    func updateWorkStudentsNarrowsToTheirCopies() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Operations")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Simma", lastName: "Zeller")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", lastName: "Fried")
        CoreDataTestHelpers.save(context)
        _ = try await tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Simma"), .string("Naomi")])
        ])
        let items = workItems(in: context)
        #expect(items.count == 2)
        let simmas = try #require(items.first { $0.title.isEmpty || true })

        let receipt = try await tool(named: "update_work", in: tools).handler([
            "work_id": .string(try #require(simmas.id).uuidString),
            "status": .string("mastered"),
            "students": .array([.string("Naomi")])
        ])

        #expect(receipt.contains("for Naomi Fried"))
        let byStudent = Dictionary(uniqueKeysWithValues: items.map { ($0.studentID, $0) })
        let naomi = try #require(context.safeFetch(CDFetchRequest(CDStudent.self)).first { $0.firstName == "Naomi" })
        let simma = try #require(context.safeFetch(CDFetchRequest(CDStudent.self)).first { $0.firstName == "Simma" })
        #expect(byStudent[try #require(naomi.id).uuidString]?.status == .mastered)
        #expect(byStudent[try #require(simma.id).uuidString]?.status == .active)
    }

    @Test("update_work with students refuses a shared project row")
    func updateWorkStudentsRefusesSharedRow() async throws {
        let (tools, context) = try makeTools()
        let simma = CoreDataTestHelpers.seedStudent(in: context, firstName: "Simma", lastName: "Zeller")
        let naomi = CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", lastName: "Fried")
        let shared = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Fundamental Needs poster",
            studentID: try #require(simma.id), lessonID: UUID()
        )
        for student in [simma, naomi] {
            let participant = CDWorkParticipantEntity(context: context)
            participant.id = UUID()
            participant.studentID = try #require(student.id).uuidString
            participant.work = shared
        }
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_work", in: tools).handler([
                "work_id": .string(try #require(shared.id).uuidString),
                "status": .string("mastered"),
                "students": .array([.string("Naomi")])
            ])
        }
        #expect(shared.status == .active)
    }
}
