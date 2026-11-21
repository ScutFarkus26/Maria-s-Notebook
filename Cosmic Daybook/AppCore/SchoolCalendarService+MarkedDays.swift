//
//  SchoolCalendarService+MarkedDays.swift
//  Cosmic Daybook
//
//  What turning a day with attendance marks into a day off does to them:
//  the marks stay on the record, but the totals stop counting them
//  (`AttendanceTallies`, domain-logic review 2026-11-20, R19). Whoever makes
//  such a day off says so with this sentence.
//

import CoreData
import Foundation

extension SchoolCalendarService {

    /// "Attendance was already marked on Mon, Nov 23 (12 children). Those
    /// marks stay on the record but no longer count in the attendance
    /// totals." for the days among `days` that hold marks, or nil when none
    /// does. Read after the change, so only days now off are named.
    func markedDaysOffNotice(for days: [Date], using context: NSManagedObjectContext) -> String? {
        let marked = days.compactMap { day -> (Date, Int)? in
            guard isNonSchoolDaySync(day, using: context) else { return nil }
            let count = Self.markedChildren(on: day, in: context)
            return count > 0 ? (cal.startOfDay(for: day), count) : nil
        }
        guard !marked.isEmpty else { return nil }
        let list = marked.map { day, count in
            let children = count == 1 ? "1 child" : "\(count) children"
            return "\(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) (\(children))"
        }
        let those = marked.count == 1 && marked[0].1 == 1 ? "That mark stays" : "Those marks stay"
        return "Attendance was already marked on \(list.joined(separator: ", ")). "
            + "\(those) on the record but no longer count in the attendance totals."
    }

    /// How many children hold a mark on `day`, CloudKit duplicates folded.
    static func markedChildren(on day: Date, in context: NSManagedObjectContext) -> Int {
        let start = AppCalendar.startOfDay(day)
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@", start as NSDate, AppCalendar.addingDays(1, to: start) as NSDate
        )
        return context.safeFetch(request).deduplicatedPerStudentDay().count(where: AttendanceDeduplication.isMarked)
    }
}
