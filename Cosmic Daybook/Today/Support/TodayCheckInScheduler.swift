// TodayCheckInScheduler.swift
// Putting quiet work on a day to be checked, from Today's Gone quiet rows.
//
// The Lessons & Work grid's Schedule write (`WorkCheckInService.scheduleCheck`):
// the work's earliest *scheduled* check-in moves to the day, or one is made.
// The due date is the guide's and is left alone (domain logic review
// 2026-11-20, R4). A check-in still ahead takes the row off Gone quiet
// (`TodayScheduleBuilder`).

import CoreData
import Foundation

enum TodayCheckInScheduler {

    /// Schedules every work for `day`. Does not save.
    static func schedule(_ works: [CDWorkModel], on day: Date, in context: NSManagedObjectContext) {
        let service = WorkCheckInService(context: context)
        for work in works {
            service.scheduleCheck(for: work, on: day)
        }
    }
}
