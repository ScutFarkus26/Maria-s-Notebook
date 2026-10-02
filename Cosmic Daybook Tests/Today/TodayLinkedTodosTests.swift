import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Today Linked Todos")
struct TodayLinkedTodosTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private static func day(_ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private static func todo(
        _ work: UUID?, due: Date? = nil, done: Bool = false, id: UUID = UUID()
    ) -> TodayLinkedTodos.Todo {
        TodayLinkedTodos.Todo(id: id, linkedWorkItemID: work?.uuidString, dueDate: due, isCompleted: done)
    }

    private static func build(
        _ todos: [TodayLinkedTodos.Todo], onScreen: Set<UUID>, today: Date = day(9, 20)
    ) -> TodayLinkedTodos {
        TodayLinkedTodos.build(todos: todos, workIDsOnScreen: onScreen, referenceDay: today, calendar: calendar)
    }

    @Test("Open todos fold onto their on-screen work and leave the Todos list")
    func foldsAndHidesOnScreenWork() throws {
        let shown = UUID()
        let offScreen = UUID()
        let first = Self.todo(shown, due: Self.day(9, 25))
        let second = Self.todo(shown, due: Self.day(9, 22))
        let elsewhere = Self.todo(offScreen)
        let unlinked = Self.todo(nil)

        let result = Self.build([first, second, elsewhere, unlinked], onScreen: [shown])

        let row = try #require(result.byWork[shown])
        #expect(row.todoIDs == [second.id, first.id])
        #expect(row.count == 2)
        #expect(result.byWork[offScreen] == nil)
        #expect(result.hiddenTodoIDs == [first.id, second.id])
    }

    @Test("Completed todos neither fold nor hide")
    func ignoresCompleted() {
        let work = UUID()
        let done = Self.todo(work, done: true)
        let result = Self.build([done], onScreen: [work])
        #expect(result.byWork.isEmpty)
        #expect(result.hiddenTodoIDs.isEmpty)
    }

    @Test("A lowercase or padded stored id still matches the work")
    func matchesStoredIDLoosely() {
        let work = UUID()
        let todo = TodayLinkedTodos.Todo(
            id: UUID(), linkedWorkItemID: " \(work.uuidString.lowercased()) ", dueDate: nil
        )
        let result = Self.build([todo], onScreen: [work])
        #expect(result.hiddenTodoIDs == [todo.id])
    }

    @Test("A garbage link is ignored")
    func ignoresGarbageLink() {
        let todo = TodayLinkedTodos.Todo(id: UUID(), linkedWorkItemID: "not-a-uuid", dueDate: nil)
        let result = Self.build([todo], onScreen: [UUID()])
        #expect(result == .empty)
    }

    @Test("Overdue means the earliest due date is before the reference day")
    func overdueAgainstReferenceDay() {
        let work = UUID()
        let today = Self.day(9, 20, hour: 15)
        let dueYesterday = Self.build([Self.todo(work, due: Self.day(9, 19, hour: 23))], onScreen: [work], today: today)
        let dueToday = Self.build([Self.todo(work, due: Self.day(9, 20, hour: 0))], onScreen: [work], today: today)
        let undated = Self.build([Self.todo(work)], onScreen: [work], today: today)

        #expect(dueYesterday.byWork[work]?.isOverdue == true)
        #expect(dueToday.byWork[work]?.isOverdue == false)
        #expect(undated.byWork[work]?.isOverdue == false)
    }

    @Test("Summary text counts the todos and names the soonest due date")
    func summaryText() {
        let work = UUID()
        let three = Self.build(
            [Self.todo(work, due: Self.day(9, 30)), Self.todo(work, due: Self.day(9, 18)), Self.todo(work)],
            onScreen: [work]
        )
        let one = Self.build([Self.todo(work)], onScreen: [work])

        #expect(three.byWork[work]?.summary == "3 todos · Sep 18")
        #expect(three.byWork[work]?.earliestDueDate == Self.day(9, 18))
        #expect(one.byWork[work]?.summary == "1 todo")
    }

    @Test("Undated todos keep their given order after the dated ones")
    func stableOrder() {
        let work = UUID()
        let first = Self.todo(work)
        let second = Self.todo(work)
        let dated = Self.todo(work, due: Self.day(10, 1))
        let result = Self.build([first, second, dated], onScreen: [work])
        #expect(result.byWork[work]?.todoIDs == [dated.id, first.id, second.id])
    }

    @Test("No work on screen means nothing folds")
    func nothingOnScreen() {
        let result = Self.build([Self.todo(UUID())], onScreen: [])
        #expect(result == .empty)
    }
}
