import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)

@Suite("Chat Meeting & Follow-Up Tools")
@MainActor
struct NotebookMeetingChatToolsTests {
    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    @Test("recordStudentMeeting writes a completed meeting with goals as focus items")
    func recordStudentMeetingWritesMeetingAndGoals() async throws {
        let context = try makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let studentID = try #require(student.id)

        let tool = RecordStudentMeetingTool(contextProvider: { context })
        let output = try await tool.call(arguments: .init(
            student: "Ora",
            date: "2026-08-27",
            reflection: "Working through Skyscrapers drawers with Avital.",
            lessonRequests: "Racks and tubes; division on paper soon.",
            guideNotes: "",
            goals: ["Finish racks and tubes", "Pick a civilization"]
        ))
        #expect(output.contains("Ora Levi"))
        #expect(output.contains("2 new goal(s)"))

        let meetings = context.safeFetch(CDFetchRequest(CDStudentMeeting.self))
        #expect(meetings.count == 1)
        let meeting = try #require(meetings.first)
        #expect(meeting.studentIDUUID == studentID)
        #expect(meeting.completed)
        #expect(meeting.reflection == "Working through Skyscrapers drawers with Avital.")

        let focusItems = FocusItemService.fetchActive(studentID: studentID, context: context)
        #expect(focusItems.count == 2)
        #expect(focusItems.allSatisfy { $0.createdInMeetingIDUUID == meeting.id })
    }

    @Test("recordStudentMeeting returns the empty-content message without saving")
    func recordStudentMeetingRejectsEmptyContent() async throws {
        let context = try makeContext()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        let tool = RecordStudentMeetingTool(contextProvider: { context })
        let output = try await tool.call(arguments: .init(
            student: "Ora", date: "", reflection: "", lessonRequests: "", guideNotes: "", goals: []
        ))
        #expect(output.contains("Provide at least one"))
        #expect(context.safeFetch(CDFetchRequest(CDStudentMeeting.self)).isEmpty)
    }

    @Test("addFollowUp creates a todo tied to students with a due date")
    func addFollowUpCreatesTodo() async throws {
        let context = try makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Katz")
        CoreDataTestHelpers.save(context)
        let studentID = try #require(student.id)

        let tool = AddFollowUpTool(contextProvider: { context })
        let output = try await tool.call(arguments: .init(
            title: "Order Ellis Island books",
            notes: "Project is stalled until these land.",
            studentNames: ["Etty"],
            dueDate: "2026-09-10"
        ))
        #expect(output.contains("Order Ellis Island books"))
        #expect(output.contains("due 2026-09-10"))
        #expect(output.contains("Etty Katz"))

        let todos = context.safeFetch(CDFetchRequest(CDTodoItem.self))
        #expect(todos.count == 1)
        let todo = try #require(todos.first)
        #expect(todo.studentIDsArray == [studentID.uuidString])
        #expect(!todo.isCompleted)
    }

    @Test("resolveFollowUp completes a todo and reports an unknown id as a reply")
    func resolveFollowUpCompletesTodoAndHandlesUnknownID() async throws {
        let context = try makeContext()
        let addTool = AddFollowUpTool(contextProvider: { context })
        _ = try await addTool.call(arguments: .init(
            title: "Check I Survived titles in the library", notes: "", studentNames: [], dueDate: ""
        ))
        let todo = try #require(context.safeFetch(CDFetchRequest(CDTodoItem.self)).first)
        let todoID = try #require(todo.id?.uuidString)

        let tool = ResolveFollowUpTool(contextProvider: { context })
        let output = try await tool.call(arguments: .init(id: todoID))
        #expect(output.contains("Completed follow-up"))
        #expect(todo.isCompleted)
        #expect(todo.completedAt != nil)

        let unknown = try await tool.call(arguments: .init(id: UUID().uuidString))
        #expect(unknown.contains("was found"))
    }

    @Test("addFollowUp reports a same-day duplicate without offering force, and files nothing")
    func addFollowUpDuplicateReplyHasNoForceHint() async throws {
        let context = try makeContext()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Katz")
        CoreDataTestHelpers.save(context)

        let tool = AddFollowUpTool(contextProvider: { context })
        let arguments = AddFollowUpTool.Arguments(
            title: "Order Ellis Island books", notes: "", studentNames: ["Etty"], dueDate: ""
        )
        _ = try await tool.call(arguments: arguments)
        let repeated = try await tool.call(arguments: arguments)

        #expect(repeated.contains("already exists"))
        #expect(repeated.hasSuffix("Nothing was filed."))
        #expect(!repeated.contains("force"))
        #expect(context.safeFetch(CDFetchRequest(CDTodoItem.self)).count == 1)
    }

    @Test("listOpenFollowUps reports sections and filters by student")
    func listOpenFollowUpsReportsAndFilters() async throws {
        let context = try makeContext()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Katz")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Zell")
        CoreDataTestHelpers.save(context)

        let addTool = AddFollowUpTool(contextProvider: { context })
        _ = try await addTool.call(arguments: .init(
            title: "Order Morse code books", notes: "", studentNames: ["Etty"], dueDate: ""
        ))
        let meetingTool = RecordStudentMeetingTool(contextProvider: { context })
        _ = try await meetingTool.call(arguments: .init(
            student: "Etty", date: "", reflection: "", lessonRequests: "", guideNotes: "",
            goals: ["Narrative writing from the Ellis Island trip"]
        ))

        let tool = ListOpenFollowUpsTool(contextProvider: { context })
        let output = try await tool.call(arguments: .init(studentName: ""))
        #expect(output.contains("Follow-up todos:"))
        #expect(output.contains("Order Morse code books"))
        #expect(output.contains("Open student goals:"))
        #expect(output.contains("Narrative writing from the Ellis Island trip"))

        let unrelated = try await tool.call(arguments: .init(studentName: "Sarah"))
        #expect(unrelated.contains("Nothing is open for Sarah Zell."))
    }
}

#endif
