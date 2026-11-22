import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Today's to-do rule (bug hunt 2026-10-10, P2 #25; #26's quick moves went with
/// the Todos screen on 2026-11-22, #28's templates retired 2026-11, and #30's
/// Upcoming order with the screen).
@Suite("Todos: Today")
@MainActor
struct TodoListFix1010Tests {

    private static var today: Date { AppCalendar.startOfDay(Date()) }

    private static func todo(
        _ title: String, due: Int? = nil, scheduled: Int? = nil, someday: Bool = false, done: Bool = false,
        in context: NSManagedObjectContext
    ) -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.title = title
        todo.dueDate = due.map { AppCalendar.addingDays($0, to: today) }
        todo.scheduledDate = scheduled.map { AppCalendar.addingDays($0, to: today) }
        todo.isSomeday = someday
        todo.isCompleted = done
        return todo
    }

    // MARK: - Today

    @Test("Today holds overdue todos and ones due today, whatever their When date")
    func todayIncludesOverdueAndDueToday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let inToday = [
            Self.todo("Overdue", due: -3, in: context),
            Self.todo("Due today, planned for tomorrow", due: 0, scheduled: 1, in: context),
            Self.todo("Planned yesterday, not done", scheduled: -1, in: context),
            Self.todo("Planned today", scheduled: 0, in: context),
            Self.todo("Overdue, rescheduled later", due: -3, scheduled: 2, in: context),
            // A passed deadline brings a Someday todo back (bug hunt 2026-11-03, #57).
            Self.todo("Overdue but someday", due: -3, someday: true, in: context)
        ]
        let notInToday = [
            Self.todo("Planned tomorrow", scheduled: 1, in: context),
            Self.todo("Due next week", due: 7, in: context),
            Self.todo("Due next week but someday", due: 7, someday: true, in: context),
            Self.todo("Done yesterday", due: -1, done: true, in: context),
            Self.todo("No date", in: context)
        ]

        for todo in inToday {
            #expect(TodoListFilter.isOnToday(todo), "\(todo.title)")
        }
        for todo in notInToday {
            #expect(!TodoListFilter.isOnToday(todo), "\(todo.title)")
        }
    }
}
