import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-12, agent MR, continued: mastery evidence (#7),
// record_parent_communication's monthly reports and sent dates (#10, #11),
// former families (#12), repeat ordinals under `since` (#13), the smaller
// items (#14) and draft_parent_report's no-op replies (#20).

@Suite("MCP families, history and reports (Fix1012MR)")
@MainActor
struct MCPReadToolsFix1012MRTests {
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

    private func refusal(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async -> String? {
        do {
            _ = try await call(name, arguments, in: tools)
            return nil
        } catch let error as MCPToolError {
            return error.message
        } catch {
            return "unexpected: \(error)"
        }
    }

    // MARK: - #7 / #14: mastery_candidates

    @Test("Keep Practicing and Incomplete practice are not evidence of mastery")
    func keepPracticingIsNotEvidence() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Frame", area: "Math", sequence: "Operations"
        )
        let lessonID = try #require(lesson.id)
        var expected: [String: WorkStatus] = [:]
        for (first, status) in [("Ora", WorkStatus.keepPracticing), ("Etty", .incomplete), ("Dalia", .mastered)] {
            let student = CoreDataTestHelpers.seedStudent(in: context, firstName: first, lastName: "Test")
            let studentID = try #require(student.id)
            _ = PresentationFactory.makePresented(
                lesson: lesson, students: [student],
                presentedAt: try CoreDataTestHelpers.day("2026-09-01"), context: context
            )
            let row = CDLessonPresentation(context: context)
            row.studentID = studentID.uuidString
            row.lessonID = lessonID.uuidString
            row.state = .presented
            row.presentedAt = try CoreDataTestHelpers.day("2026-09-01")
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Bead frame practice", studentID: studentID, lessonID: lessonID
            )
            work.kind = .practiceLesson
            work.status = status
            work.completedAt = try CoreDataTestHelpers.day("2026-09-10")
            expected[first] = status
        }
        #expect(CoreDataTestHelpers.save(context))

        let output = try await call("mastery_candidates", [:], in: tools)

        #expect(!output.contains("Ora Test"), "Keep Practicing is not mastery")
        #expect(!output.contains("Etty Test"), "Incomplete is not mastery")
        #expect(output.contains("Dalia Test:"))
        #expect(output.contains("practice mastered"))
        #expect(expected.count == 3)
    }

    @Test("a confirmation is not dated with the latest giving")
    func confirmationIsNotDatedAsTheLatestGiving() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Frame", area: "Math", sequence: "Operations"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let first = PresentationFactory.makePresented(
            lesson: lesson, students: [ora], presentedAt: try CoreDataTestHelpers.day("2026-03-02"), context: context
        )
        first.confirmStudent(try #require(ora.id))
        _ = PresentationFactory.makePresented(
            lesson: lesson, students: [ora], presentedAt: try CoreDataTestHelpers.day("2026-09-08"), context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let output = try await call("mastery_candidates", [:], in: tools)

        #expect(!output.contains("confirmed ready 2026-09-08"))
        #expect(output.contains("confirmed ready (last given 2026-09-08)"))
    }

    // MARK: - #10 / #11: record_parent_communication

    @discardableResult
    private func seedMonthlyReport(
        for student: CDStudent, month: String, in context: NSManagedObjectContext
    ) throws -> CDParentCommunication {
        let report = CDParentCommunication(context: context)
        report.id = UUID()
        report.studentID = try #require(student.id).uuidString
        report.monthKey = month
        report.communicationType = .monthlyReport
        report.subject = "September report"
        report.body = "The guide's own words."
        report.status = .draft
        return report
    }

    @Test("a second monthly report for the same child and month is refused")
    func secondMonthlyReportIsRefused() async throws {
        let (tools, context) = try makeTools()
        let sam = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        let existing = try seedMonthlyReport(for: sam, month: "2026-09", in: context)
        CoreDataTestHelpers.save(context)

        let message = await refusal("record_parent_communication", [
            "student_name": .string("Sam"),
            "type": .string("monthlyReport"),
            "month": .string("2026-9"),
            "subject": .string("Another September report")
        ], in: tools)

        let text = try #require(message)
        #expect(text.contains("[communication id=\(try #require(existing.id).uuidString)]"))
        #expect(text.contains("draft_parent_report"))
        #expect(context.safeFetch(CDFetchRequest(CDParentCommunication.self)).count == 1)
    }

    @Test("month is read as a report month: 2026-9 is September, a word is refused")
    func monthIsParsedAsAReportMonth() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Ross")
        CoreDataTestHelpers.save(context)

        _ = try await call("record_parent_communication", [
            "student_name": .string("Eli"),
            "type": .string("monthlyReport"),
            "month": .string("2026-9"),
            "subject": .string("September report")
        ], in: tools)
        let filed = try #require(context.safeFetch(CDFetchRequest(CDParentCommunication.self)).first)
        #expect(filed.monthKey == "2026-09")

        let message = await refusal("record_parent_communication", [
            "student_name": .string("Eli"),
            "subject": .string("Note"),
            "month": .string("September")
        ], in: tools)
        #expect(message?.contains("YYYY-MM") == true)
        #expect(context.safeFetch(CDFetchRequest(CDParentCommunication.self)).count == 1)
    }

    @Test("sent_date on its own marks the communication sent")
    func sentDateMeansSent() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        CoreDataTestHelpers.save(context)

        _ = try await call("record_parent_communication", [
            "student_name": .string("Sam"),
            "subject": .string("Conference notes"),
            "sent_date": .string("2026-09-14")
        ], in: tools)

        let communication = try #require(context.safeFetch(CDFetchRequest(CDParentCommunication.self)).first)
        // `status` reads sent whenever a date is set; the stored status is what
        // was left saying draft, and what the reply's "marked sent" now matches.
        #expect(communication.statusRaw == MonthlyReportStatus.sent.rawValue)
        #expect(communication.sentAt == (try CoreDataTestHelpers.day("2026-09-14")))
    }

    @Test("sent_date with a status other than sent is refused")
    func sentDateWithAnotherStatusIsRefused() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        CoreDataTestHelpers.save(context)

        let message = await refusal("record_parent_communication", [
            "student_name": .string("Sam"),
            "subject": .string("Conference notes"),
            "status": .string("draft"),
            "sent_date": .string("2026-09-14")
        ], in: tools)

        #expect(message?.contains("sent_date") == true)
        #expect(context.safeFetch(CDFetchRequest(CDParentCommunication.self)).isEmpty)
    }

    // MARK: - #12: list_guardians

    @Test("the whole-class guardian list leaves out families of children who left")
    func guardiansListLeavesOutFormerFamilies() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let rivka = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rivka", lastName: "Gold", enrollmentStatus: .withdrawn
        )
        for (student, name) in [(maya, "Rosa Soto"), (rivka, "Dina Gold")] {
            let guardian = CDGuardian(context: context)
            guardian.id = UUID()
            guardian.studentID = try #require(student.id).uuidString
            guardian.name = name
            guardian.email = "\(name.prefix(4).lowercased())@example.com"
        }
        CoreDataTestHelpers.save(context)

        let everyone = try await call("list_guardians", [:], in: tools)
        #expect(everyone.contains("Rosa Soto"))
        #expect(!everyone.contains("Dina Gold"))

        let hers = try await call("list_guardians", ["student_name": .string("Rivka Gold")], in: tools)
        #expect(hers.contains("Dina Gold"), "asking for her by name still finds her family")
    }

    // MARK: - #13: student_presentation_history

    @Test("since still numbers a repeat from the whole record")
    func historySinceKeepsTheOrdinal() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        _ = PresentationFactory.makePresented(
            lesson: lesson, students: [ora], presentedAt: try CoreDataTestHelpers.day("2026-03-02"), context: context
        )
        _ = PresentationFactory.makePresented(
            lesson: lesson, students: [ora], presentedAt: try CoreDataTestHelpers.day("2026-09-08"), context: context
        )
        CoreDataTestHelpers.save(context)

        let output = try await call("student_presentation_history", [
            "student_name": .string("Ora"), "since": .string("2026-09-01")
        ], in: tools)

        #expect(output.contains("2026-09-08 — Checkerboard (2nd time)"))
        #expect(!output.contains("2026-03-02"))
    }

    // MARK: - #14: the smaller items

    @Test("student_observations names the child in full")
    func observationsHeaderUsesTheFullName() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)

        let output = try await call("student_observations", ["student_name": .string("Etty Klein")], in: tools)

        #expect(output.contains("No notes about Etty Klein"))
    }

    @Test("update_going_out to completed dates the outing, as the app's button does")
    func completedGoingOutGetsADate() async throws {
        let (tools, context) = try makeTools()
        let receipt = try await call("update_going_out", ["title": .string("Museum")], in: tools)
        let goingOut = try #require(context.safeFetch(CDFetchRequest(CDGoingOut.self)).first)
        #expect(receipt.contains("Proposed"))
        #expect(goingOut.actualDate == nil)

        _ = try await call("update_going_out", [
            "going_out_id": .string(try #require(goingOut.id).uuidString),
            "status": .string("completed")
        ], in: tools)

        #expect(goingOut.status == .completed)
        let actual = try #require(goingOut.actualDate)
        #expect(AppCalendar.shared.isDateInToday(actual))
    }

    // MARK: - #20: draft_parent_report's no-op replies

    private func outcome(of block: () async throws -> String) async throws -> MCPCallOutcome {
        let outcome = MCPCallOutcome()
        _ = try await MCPCallOutcome.$current.withValue(outcome) { try await block() }
        return outcome
    }

    @Test("draft_parent_report's \"already has a draft\" and \"no evidence\" replies are not journaled")
    func draftReportNoOpsWriteNothing() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let dependencies = AppDependencies(coreDataStack: stack)
        let tools = MCPNotebookTools.makeTools(context: { context }, dependencies: { dependencies })
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        try seedMonthlyReport(for: ora, month: "2026-08", in: context)
        CoreDataTestHelpers.save(context)

        let kept = try await outcome {
            try await call("draft_parent_report", [
                "student_name": .string("Ora"), "month": .string("2026-08")
            ], in: tools)
        }
        #expect(kept.wroteNothing)

        let empty = try await outcome {
            try await call("draft_parent_report", [
                "student_name": .string("Etty"), "month": .string("2026-08")
            ], in: tools)
        }
        #expect(empty.wroteNothing)
    }
}
