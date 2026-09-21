import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Clearing a WatchList row acts on its source the way the source's own
/// screen would: unflag, complete (recurrence included), resolve.
@Suite("WatchList Actions")
@MainActor
struct WatchListActionsTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func item(_ kind: WatchItemKind, sourceID: UUID, studentID: UUID? = UUID()) -> WatchItem {
        WatchItem(kind: kind, sourceID: sourceID, studentID: studentID, text: "", date: Date(), dueDate: nil)
    }

    @Test("Clearing a note row unflags the note and bumps its updated date")
    func clearNote() throws {
        let context = try makeContext()
        let student = try #require(CoreDataTestHelpers.seedStudent(in: context).id)
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Watch the carries.")
        note.scope = .student(student)
        note.needsFollowUp = true
        let earlier = Date(timeIntervalSinceNow: -3_600)
        note.updatedAt = earlier
        CoreDataTestHelpers.save(context)

        let cleared = WatchListActions.clear(item(.flaggedNote, sourceID: try #require(note.id)), in: context)

        #expect(cleared)
        #expect(note.needsFollowUp == false)
        #expect(try #require(note.updatedAt) > earlier)
        #expect(!context.hasChanges)
    }

    @Test("Clearing a todo row completes it, and a weekly todo spawns one new occurrence a week later")
    func clearRecurringTodo() throws {
        let context: NSManagedObjectContext = try makeContext()
        let student: UUID = UUID()
        let due: Date = AppCalendar.startOfDay(Date())
        let todo: CDTodoItem = CDTodoItem(context: context)
        todo.title = "Watch Ora with the checkerboard"
        todo.resolvedStudentIDs = [student]
        todo.dueDate = due
        todo.recurrence = .weekly
        CoreDataTestHelpers.save(context)

        let todoID: UUID = try #require(todo.id)
        let cleared: Bool = WatchListActions.clear(
            item(.watchTodo, sourceID: todoID, studentID: student), in: context
        )

        #expect(cleared)
        #expect(todo.isCompleted)
        #expect(todo.completedAt != nil)
        let all: [CDTodoItem] = context.safeFetch(CDFetchRequest(CDTodoItem.self))
        let open: [CDTodoItem] = all.filter { !$0.isCompleted }
        #expect(open.count == 1)
        let next: CDTodoItem = try #require(open.first)
        let expectedStudents: [UUID] = [student]
        let expectedDue: Date = AppCalendar.addingDays(7, to: due)
        #expect(next.title == todo.title)
        #expect(next.resolvedStudentIDs == expectedStudents)
        #expect(next.dueDate == expectedDue)
    }

    @Test("Clearing a goal row resolves it with a time and no meeting")
    func clearGoal() throws {
        let context = try makeContext()
        let student = UUID()
        let goal = FocusItemService.create(
            studentID: student, text: "Finish racks and tubes", meetingID: UUID(), sortOrder: 0, context: context
        )
        CoreDataTestHelpers.save(context)

        let cleared = WatchListActions.clear(
            item(.goal, sourceID: try #require(goal.id), studentID: student), in: context
        )

        #expect(cleared)
        #expect(goal.status == .resolved)
        #expect(goal.resolvedAt != nil)
        #expect(goal.resolvedInMeetingID == nil)
    }

    @Test("Clearing a row whose source is gone returns false and throws nothing")
    func clearMissingSource() throws {
        let context = try makeContext()
        for kind in WatchItemKind.allCases {
            #expect(WatchListActions.clear(item(kind, sourceID: UUID()), in: context) == false)
        }
        #expect(!context.hasChanges)
    }

    @Test("Opening a goal row finds its meeting, or falls back to the child")
    func openGoal() throws {
        let context: NSManagedObjectContext = try makeContext()
        let student: UUID = UUID()
        let meeting: CDStudentMeeting = CDStudentMeeting(context: context)
        meeting.studentIDUUID = student
        let meetingID: UUID = try #require(meeting.id)
        let withMeeting: CDStudentFocusItem = FocusItemService.create(
            studentID: student, text: "A", meetingID: meetingID, sortOrder: 0, context: context
        )
        let orphan: CDStudentFocusItem = FocusItemService.create(
            studentID: student, text: "B", meetingID: UUID(), sortOrder: 1, context: context
        )
        CoreDataTestHelpers.save(context)
        let withMeetingID: UUID = try #require(withMeeting.id)
        let orphanID: UUID = try #require(orphan.id)

        let first: WatchSource? = WatchListActions.open(
            item(.goal, sourceID: withMeetingID, studentID: student), in: context
        )
        guard case .meeting(let found, let foundStudent)? = first else {
            Issue.record("Expected a meeting source")
            return
        }
        #expect(found?.objectID == meeting.objectID)
        #expect(foundStudent == student)

        let second: WatchSource? = WatchListActions.open(
            item(.goal, sourceID: orphanID, studentID: student), in: context
        )
        guard case .meeting(let missing, _)? = second else {
            Issue.record("Expected a meeting source")
            return
        }
        #expect(missing == nil)
        let gone: WatchSource? = WatchListActions.open(item(.flaggedNote, sourceID: UUID()), in: context)
        #expect(gone == nil)
    }
}
