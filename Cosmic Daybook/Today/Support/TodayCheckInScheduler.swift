// TodayCheckInScheduler.swift
// Putting quiet work on a day to be checked, from Today's Gone quiet rows.
//
// The Lessons & Work grid's Schedule write, with one difference: the work's
// earliest *scheduled* check-in moves to the day, or one is made. The grid
// moves its earliest check-in of any status, which on work that has gone
// quiet would usually be one already done, and would take that check off
// the record. The due date follows, so the two never drift. A check-in still
// ahead takes the row off Gone quiet (`TodayScheduleBuilder`).

import CoreData
import Foundation

enum TodayCheckInScheduler {

    /// Schedules every work for `day`. Does not save.
    static func schedule(_ works: [CDWorkModel], on day: Date, in context: NSManagedObjectContext) {
        let checkDay = AppCalendar.startOfDay(day)
        for work in works {
            let earliest = WorkLogService.scheduledCheckIns(of: work, in: context)
                .min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            if let earliest {
                earliest.date = checkDay
                if earliest.work == nil { earliest.work = work }
            } else {
                CDWorkCheckIn.make(for: work, on: checkDay, purpose: "progressCheck", in: context)
            }
            work.dueAt = checkDay
        }
    }
}
