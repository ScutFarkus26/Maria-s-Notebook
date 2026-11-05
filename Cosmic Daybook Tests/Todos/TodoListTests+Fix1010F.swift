import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Todos screen's lists and quick moves (bug hunt 2026-10-10, P2 #25,
/// #26 and #30's Upcoming order; #28's templates retired 2026-11).
@Suite("Todos: Today, quick moves and Upcoming")
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

    // MARK: - Quick moves

    @Test("The batch Today button plans the todos for today, as the swipe does, and keeps their deadlines")
    func batchTodayMovesTheWhenDate() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let someday = Self.todo("Someday", someday: true, in: context)
        let dueLater = Self.todo("Due Friday", due: 4, scheduled: 3, in: context)

        TodoScheduling.moveToToday([someday, dueLater])

        for todo in [someday, dueLater] {
            #expect(todo.scheduledDate == Self.today)
            #expect(!todo.isSomeday)
            #expect(TodoListFilter.isOnToday(todo))
        }
        #expect(dueLater.dueDate == AppCalendar.addingDays(4, to: Self.today))
        #expect(someday.dueDate == nil)
    }

    @Test("Next Week is the coming Monday")
    func nextWeekIsMonday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AppCalendar.shared.timeZone
        for day in 4...11 {   // Sunday 4 October 2026 through the next Sunday
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 15)))
            let monday = TodoScheduling.nextMonday(after: date)
            #expect(calendar.component(.weekday, from: monday) == 2)
            #expect(monday > date)
            #expect(monday <= AppCalendar.addingDays(7, to: AppCalendar.startOfDay(date)))
        }
    }

    // MARK: - Upcoming

    @Test("Upcoming's day headings run into the new year in order")
    func upcomingDaysCrossTheNewYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AppCalendar.shared.timeZone
        let december28 = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 28)))
        let days = [30, 31, 33, 35].map { AppCalendar.addingDays($0 - 28, to: december28) }
        let keys = days.map(TodoMainView.upcomingDayKey).shuffled()

        let sorted = keys.sorted {
            (TodoMainView.upcomingDayDate($0, today: december28) ?? .distantFuture)
                < (TodoMainView.upcomingDayDate($1, today: december28) ?? .distantFuture)
        }
        #expect(sorted == days.map(TodoMainView.upcomingDayKey))
        #expect(TodoMainView.upcomingDayDate(TodoMainView.upcomingDayKey(days[2]), today: december28) == days[2])
    }
}
