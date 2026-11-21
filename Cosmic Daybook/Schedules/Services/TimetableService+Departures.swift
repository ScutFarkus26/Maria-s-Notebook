// TimetableService+Departures.swift
// Taking a child out of every group from a day on, as a This Day and After
// edit would: the departure step (plan "Domain logic fixes", Phase 7) calls it
// when she leaves the class, so she isn't left in a co-teacher's group.

import CoreData
import Foundation

extension TimetableService {

    /// Takes `studentID` out of every block from `day` on: each weekly block
    /// she is in ends the day before and a copy without her starts on `day`
    /// (one that begins on or after `day` is edited in place), and every
    /// one-off and day's change from `day` on loses her too. Earlier days keep
    /// her. Running it again changes nothing. Returns how many blocks, one-offs
    /// and changes it changed. Does not save.
    @discardableResult
    static func takeOutOfGroups(
        studentID: String,
        from day: Date,
        in context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) -> Int {
        let key = studentID.uppercased()
        let start = calendar.startOfDay(for: day)
        func without(_ values: TimetableBlockValues) -> TimetableBlockValues? {
            guard values.studentIDs.contains(where: { $0.uppercased() == key }) else { return nil }
            var result = values
            result.studentIDs.removeAll { $0.uppercased() == key }
            return result
        }
        var changed = 0
        let blocks = context.safeFetch(CDFetchRequest(CDTimetableBlock.self)).filter { !$0.isDeleted }
        for block in blocks {
            guard let values = without(block.values) else { continue }
            if let onDay = block.onDay {
                guard calendar.startOfDay(for: onDay) >= start else { continue }
                touch(block, with: values, now: now)
            } else {
                guard isRunning(block, onOrAfter: start, calendar: calendar) else { continue }
                _ = split(block, from: start, values: values, in: context, now: now, calendar: calendar)
            }
            changed += 1
        }
        let request = CDFetchRequest(CDTimetableChange.self)
        request.predicate = NSPredicate(format: "day >= %@", start as NSDate)
        for change in context.safeFetch(request) where !change.isDeleted && change.kind == .changed {
            guard let values = without(change.values) else { continue }
            change.values = values
            change.modifiedAt = now
            changed += 1
        }
        return changed
    }
}
