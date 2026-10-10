// TodoScheduling.swift
// The one-tap moves of a todo's When date.

import Foundation

/// The quick moves the row's swipe and menu, and the list's batch Today
/// button, make: each sets the When date and takes the todo out of Someday,
/// and leaves its deadline as it is. The batch button used to set the
/// deadline instead, so the todos it "moved to Today" stayed where they were
/// (bug hunt 2026-10-10, P2 #26).
enum TodoScheduling {

    static func moveToToday(_ todos: some Sequence<CDTodoItem>, now: Date = Date()) {
        schedule(todos, on: AppCalendar.startOfDay(now))
    }

    static func moveToTomorrow(_ todo: CDTodoItem, now: Date = Date()) {
        schedule([todo], on: AppCalendar.addingDays(1, to: AppCalendar.startOfDay(now)))
    }

    static func moveToNextWeek(_ todo: CDTodoItem, now: Date = Date()) {
        schedule([todo], on: nextMonday(after: now))
    }

    static func moveToSomeday(_ todo: CDTodoItem) {
        todo.scheduledDate = nil
        todo.isSomeday = true
    }

    static func removeDates(_ todo: CDTodoItem) {
        todo.scheduledDate = nil
        todo.dueDate = nil
        todo.isSomeday = false
    }

    /// The start of the first Monday after `date`'s day.
    static func nextMonday(after date: Date) -> Date {
        let calendar = AppCalendar.shared
        var day = AppCalendar.addingDays(1, to: AppCalendar.startOfDay(date))
        while calendar.component(.weekday, from: day) != 2 {
            day = AppCalendar.addingDays(1, to: day)
        }
        return day
    }

    private static func schedule(_ todos: some Sequence<CDTodoItem>, on day: Date) {
        for todo in todos {
            todo.scheduledDate = day
            todo.isSomeday = false
        }
    }
}
