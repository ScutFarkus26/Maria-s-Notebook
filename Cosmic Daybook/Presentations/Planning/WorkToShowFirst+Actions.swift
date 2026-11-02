// WorkToShowFirst+Actions.swift
// What the "to check first" lists do with a row: log it from the present
// sheet.
//
// The row is re-checked before writing, because a list can be older than the
// work: the row may have been logged in the work sheet, on another device or
// over MCP since it was read. A shared row (project or book-club work) is one
// row for everyone on it, so it is never logged from here; logging it would
// close it for her classmates too.

import CoreData
import Foundation

extension WorkToShowFirst {

    // MARK: - Logging from the present sheet

    /// Why a row wasn't logged.
    enum LogRefusal: Error, Equatable {
        /// Logged, closed or deleted since the list was read.
        case noLongerOpen
        /// A row other children are on too: logging it would close theirs.
        case sharedWithOthers
    }

    /// Logs one row for its child through `WorkLogService.log`, as every
    /// other log does, so it comes with an Undo. Refuses a row that is no
    /// longer open for her, and one whose log would close anyone else's part.
    static func log(
        _ item: Item,
        as status: WorkStatus,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator?
    ) throws -> WorkLogService.Receipt {
        let work = item.work
        guard !work.isDeleted, work.managedObjectContext != nil, work.status.isOpen,
              QuietStudentsOrder.openStudentIDs(of: work).contains(item.studentID) else {
            throw LogRefusal.noLongerOpen
        }
        guard WorkLogService.studentsLogged(on: work, in: context) == [item.studentID] else {
            throw LogRefusal.sharedWithOthers
        }
        return try WorkLogService.log(
            [WorkLogService.Entry(work: work, status: status)],
            context: context,
            saveCoordinator: saveCoordinator
        )
    }

    // MARK: - Days

    /// "Today", "Thursday" within the coming week, else "Thu, Oct 23": a
    /// weekday alone more than six days out would name the wrong week.
    static func dayName(_ day: Date, now: Date = Date()) -> String {
        let calendar = AppCalendar.shared
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if isWithinTheWeek(day, now: now) { return day.formatted(.dateTime.weekday(.wide)) }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// One to six days after `now`'s day.
    private static func isWithinTheWeek(_ day: Date, now: Date) -> Bool {
        let days = AppCalendar.shared.dateComponents(
            [.day], from: AppCalendar.startOfDay(now), to: AppCalendar.startOfDay(day)
        ).day ?? 0
        return (1...6).contains(days)
    }
}
