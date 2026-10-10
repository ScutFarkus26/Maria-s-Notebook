// PracticeCheckInScheduler.swift
// Record Practice's "Schedule Check-in".
//
// The toggle used to write only `checkInScheduledFor` on the practice session,
// a date nothing schedules from: no check-in appeared on the work, the
// calendar or Today. It now makes a real check-in on each work row the
// session covers, through `CDWorkCheckIn.make`, the one constructor every
// other check-in uses. The session keeps the date too, for its own card.

import CoreData
import Foundation

enum PracticeCheckInScheduler {

    /// Schedules a check-in on `day` for each of `works`, except a row that
    /// already has a scheduled or completed one that day (a skipped one
    /// doesn't count, as in `update_work`'s add). Does not save.
    /// - Returns: The check-ins it made.
    @discardableResult
    static func schedule(
        on day: Date, for works: [CDWorkModel], in context: NSManagedObjectContext
    ) -> [CDWorkCheckIn] {
        let start = AppCalendar.startOfDay(day)
        var made: [CDWorkCheckIn] = []
        for work in works where work.isOpen {
            let taken = WorkLogService.checkIns(of: work, in: context).contains { checkIn in
                guard checkIn.status != .skipped, let date = checkIn.date else { return false }
                return AppCalendar.isSameDay(date, start)
            }
            guard !taken else { continue }
            made.append(CDWorkCheckIn.make(
                for: work, on: start, purpose: CheckInReason.progressCheck.rawValue, in: context
            ))
        }
        return made
    }
}
