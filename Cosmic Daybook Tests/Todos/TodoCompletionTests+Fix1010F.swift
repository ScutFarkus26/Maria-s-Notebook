import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Repeating todos (bug hunt 2026-10-10, P2 #17, #22, #23): every tick goes
/// through `TodoCompletionService`, unticking takes back the copy a tick made,
/// and the next occurrence lands on the right day.
@Suite("Todos: completing, reopening and repeating")
@MainActor
struct TodoRepeatCompletionTests {

    private static let calendar = AppCalendar.shared
    private static var today: Date { AppCalendar.startOfDay(Date()) }

    private static func todo(
        _ title: String, recurrence: RecurrencePattern, due: Date? = nil, scheduled: Date? = nil,
        in context: NSManagedObjectContext
    ) -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.title = title
        todo.recurrence = recurrence
        todo.dueDate = due
        todo.scheduledDate = scheduled
        return todo
    }

    private static func openTodos(in context: NSManagedObjectContext) -> [CDTodoItem] {
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = NSPredicate(format: "isCompleted == NO")
        return context.safeFetch(request)
    }

    // MARK: - Tick and untick

    @Test("Tick, untick, tick leaves one next occurrence, not two")
    func tickUntickTickMakesOneCopy() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let weekly = Self.todo("Water the plants", recurrence: .weekly, due: Self.today, in: context)
        #expect(context.safeSave())

        TodoCompletionService.complete(weekly)
        #expect(context.safeSave())
        #expect(Self.openTodos(in: context).count == 1)

        TodoCompletionService.reopen(weekly)
        #expect(context.safeSave())
        #expect(!weekly.isCompleted)
        #expect(weekly.completedAt == nil)
        #expect(Self.openTodos(in: context).map(\.objectID) == [weekly.objectID])

        TodoCompletionService.complete(weekly)
        #expect(context.safeSave())
        let open = Self.openTodos(in: context)
        #expect(open.count == 1)
        #expect(open.first?.dueDate == AppCalendar.addingDays(7, to: Self.today))
    }

    @Test("Unticking keeps a next occurrence someone has changed since")
    func untickKeepsAChangedCopy() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let weekly = Self.todo("Water the plants", recurrence: .weekly, due: Self.today, in: context)
        TodoCompletionService.complete(weekly)
        #expect(context.safeSave())
        let copy = try #require(Self.openTodos(in: context).first)
        copy.dueDate = AppCalendar.addingDays(9, to: Self.today)
        #expect(context.safeSave())

        TodoCompletionService.reopen(weekly)
        #expect(context.safeSave())
        #expect(Set(Self.openTodos(in: context).map(\.objectID)) == [weekly.objectID, copy.objectID])
    }

    @Test("Unticking a todo that doesn't repeat touches nothing else")
    func untickPlainTodo() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let plain = Self.todo("Order paint", recurrence: .none, due: Self.today, in: context)
        let lookalike = Self.todo("Order paint", recurrence: .none, due: Self.today, in: context)
        TodoCompletionService.complete(plain)
        #expect(context.safeSave())

        TodoCompletionService.reopen(plain)
        #expect(Set(Self.openTodos(in: context).map(\.objectID)) == [plain.objectID, lookalike.objectID])
    }

    // MARK: - Where the next one lands

    @Test("A daily todo done five days late comes back tomorrow, not overdue")
    func lateDailyRollsPastToday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let daily = Self.todo(
            "Feed the fish", recurrence: .daily, due: AppCalendar.addingDays(-5, to: Self.today), in: context
        )

        TodoCompletionService.complete(daily)

        let next = try #require(Self.openTodos(in: context).first)
        #expect(next.dueDate == AppCalendar.addingDays(1, to: Self.today))
        #expect(!next.isOverdue)
    }

    @Test("A todo with only a When date comes back with a When date and no deadline")
    func whenOnlyStaysWhenOnly() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let scheduled = AppCalendar.addingDays(-2, to: Self.today)
        let weekly = Self.todo("Tidy the shelves", recurrence: .weekly, scheduled: scheduled, in: context)

        TodoCompletionService.complete(weekly)

        let next = try #require(Self.openTodos(in: context).first)
        #expect(next.dueDate == nil)
        #expect(next.scheduledDate == AppCalendar.addingDays(5, to: Self.today))
    }

    @Test("A todo with a deadline and a When date keeps the gap between them")
    func bothDatesKeepTheirGap() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let due = AppCalendar.addingDays(3, to: Self.today)
        let weekly = Self.todo(
            "Plan the field trip", recurrence: .weekly, due: due,
            scheduled: AppCalendar.addingDays(1, to: Self.today), in: context
        )

        TodoCompletionService.complete(weekly)

        let next = try #require(Self.openTodos(in: context).first)
        #expect(next.dueDate == AppCalendar.addingDays(10, to: Self.today))
        #expect(next.scheduledDate == AppCalendar.addingDays(8, to: Self.today))
    }

    @Test("A custom repeat with no interval stored repeats every 7 days, as the editor shows")
    func customWithoutIntervalRepeatsWeekly() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let custom = Self.todo("Check the compost", recurrence: .custom, due: Self.today, in: context)
        #expect(custom.customIntervalDays == 0)

        TodoCompletionService.complete(custom)

        let next = try #require(Self.openTodos(in: context).first)
        #expect(next.dueDate == AppCalendar.addingDays(7, to: Self.today))
    }

    @Test("Choosing Custom in the editor stores the 7 days it shows")
    func choosingCustomStoresSeven() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let todo = Self.todo("Check the compost", recurrence: .none, in: context)

        todo.setRecurrence(.custom)
        #expect(todo.recurrence == .custom)
        #expect(todo.customIntervalDays == 7)

        todo.customIntervalDays = 3
        todo.setRecurrence(.weekly)
        todo.setRecurrence(.custom)
        #expect(todo.customIntervalDays == 3)
    }

    @Test("A monthly todo from the 31st goes back to the 31st after a short month")
    func monthlyFromThe31stKeepsItsDay() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // A January 31st safely in the future, so nothing is rolled past today.
        let year = Self.calendar.component(.year, from: Self.today) + 1
        let jan31 = try #require(Self.calendar.date(from: DateComponents(year: year, month: 1, day: 31)))
        let monthly = Self.todo("Send the newsletter", recurrence: .monthly, due: jan31, in: context)
        #expect(context.safeSave())

        TodoCompletionService.complete(monthly)
        #expect(context.safeSave())
        let february = try #require(Self.openTodos(in: context).first)
        let februaryDue = try #require(february.dueDate)
        let lastOfFebruary = Self.calendar.range(of: .day, in: .month, for: februaryDue)?.count
        #expect(Self.calendar.dateComponents([.month, .day], from: februaryDue)
            == DateComponents(month: 2, day: lastOfFebruary))

        TodoCompletionService.complete(february)
        #expect(context.safeSave())
        let march = try #require(Self.openTodos(in: context).first)
        #expect(Self.calendar.dateComponents([.month, .day], from: try #require(march.dueDate))
            == DateComponents(month: 3, day: 31))
    }

    // MARK: - The rule on fixed dates

    @Test("Month steps: the 31st returns after short months; a 30th stays the 30th")
    func monthStepsOnFixedDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        func day(_ month: Int, _ day: Int, _ year: Int = 2027) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
        }
        func next(due: Date, previous: Date?) throws -> Date? {
            let rule = TodoRepeatRule(
                recurrence: .monthly, customIntervalDays: 0, repeatAfterCompletion: false,
                dueDate: due, scheduledDate: nil, previousAnchorDate: previous
            )
            return try #require(rule.nextDates(today: try day(1, 1), calendar: calendar)).dueDate
        }

        #expect(try next(due: day(1, 31), previous: nil) == day(2, 28))
        #expect(try next(due: day(2, 28), previous: day(1, 31)) == day(3, 31))
        #expect(try next(due: day(3, 31), previous: day(2, 28)) == day(4, 30))
        #expect(try next(due: day(4, 30), previous: day(3, 31)) == day(5, 31))
        #expect(try next(due: day(4, 30), previous: day(3, 30)) == day(5, 30))
        #expect(try next(due: day(2, 28), previous: day(1, 28)) == day(3, 28))
    }

    @Test("Rolling on fixed dates: a weekly todo done late lands on its next weekday after today")
    func weeklyRollsOnFixedDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        let wednesdayTwoWeeksOn = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21)))
        let rule = TodoRepeatRule(
            recurrence: .weekly, customIntervalDays: 0, repeatAfterCompletion: false,
            dueDate: monday, scheduledDate: nil
        )

        let next = try #require(rule.nextDates(today: wednesdayTwoWeeksOn, calendar: calendar))
        #expect(next.dueDate == calendar.date(from: DateComponents(year: 2026, month: 10, day: 26)))
        #expect(next.scheduledDate == nil)
    }
}
