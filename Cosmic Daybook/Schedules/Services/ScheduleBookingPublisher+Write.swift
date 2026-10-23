// ScheduleBookingPublisher+Write.swift
// What one run writes: a booking per planned presentation in the window,
// never backwards, stale ones removed, and the fold of two devices' copies.

import CoreData
import Foundation

extension ScheduleBookingPublisher {

    /// Writes the bookings for the window starting today, in `context`'s
    /// guide store. Doesn't save, and deletes no copy of a booking still
    /// wanted (`fold` does that, once CloudKit has said where they are).
    static func write(in context: NSManagedObjectContext, now: Date, calendar: Calendar) -> Outcome {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: windowDays, to: today) ?? today
        var outcome = Outcome()
        var rows = Dictionary(grouping: bookings(in: context)) { $0.presentationID.uppercased() }

        for plan in ScheduleLessonPlan.planned(from: today, to: end, in: context, calendar: calendar) {
            let key = plan.id.uuidString.uppercased()
            guard let group = rows.removeValue(forKey: key), let kept = carryNewest(group, now: now) else {
                insert(plan, in: context, now: now)
                outcome.inserted += 1
                continue
            }
            let source = millis(plan.presentation.modifiedAt)
            let written = millis(kept.sourceModifiedAt)
            // Never backwards: this device knows an older plan than the one booked.
            guard source >= written, source > written || !matches(kept, plan, calendar: calendar) else { continue }
            set(kept, to: plan, now: now)
            outcome.updated += 1
        }

        // What's left has no plan in the window on this device.
        let known = presentations(Set(rows.keys), in: context)
        for (key, group) in rows {
            guard isStale(group, presentation: known[key], today: today, now: now, calendar: calendar) else { continue }
            for row in group { context.delete(row) }
            outcome.removed += group.count
        }
        return outcome
    }

    /// Whether `group`'s bookings (one presentation's) should go: the day has
    /// passed; the presentation is known here and was given, unscheduled or
    /// moved out of the window, and this device knows it at least as new as
    /// it was booked; or it's unknown here and the newest copy is over an
    /// hour old.
    private static func isStale(
        _ group: [CDTimetableBooking],
        presentation: CDLessonAssignment?,
        today: Date,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let days = group.compactMap(\.day).map(calendar.startOfDay(for:))
        if days.count == group.count, days.allSatisfy({ $0 < today }) { return true }
        if let presentation {
            let written = group.map { millis($0.sourceModifiedAt) }.max() ?? .min
            return millis(presentation.modifiedAt) >= written
        }
        let newest = group.compactMap { $0.modifiedAt ?? $0.createdAt }.max() ?? .distantPast
        return now.timeIntervalSince(newest) > unknownGrace
    }

    // MARK: - Doubles

    /// One presentation's bookings when there's more than one, each group
    /// oldest first.
    static func doubles(in context: NSManagedObjectContext) -> [[CDTimetableBooking]] {
        Dictionary(grouping: bookings(in: context)) { $0.presentationID.uppercased() }
            .values.filter { $0.count > 1 }
            .map { $0.sorted(by: madeFirst) }
    }

    /// Keeps the copy made first, with the newest values, and deletes the
    /// others it safely can: one never sent to iCloud, or in the kept copy's
    /// zone. One in another zone stays (the kept copy may still be waiting in
    /// the guide's own zone to be filed into the share, and deleting the
    /// shared one would take the booking off the Assistant meanwhile), as
    /// does one `zones` has no answer for, and a copy with the kept one's own
    /// `id`. Returns how many it deleted.
    static func fold(
        _ rows: [CDTimetableBooking], zones: ClassroomNames.ZoneMap, in context: NSManagedObjectContext
    ) -> Int {
        guard rows.count > 1, let kept = carryNewest(rows, now: nil) else { return 0 }
        let keptZone = zones.answer(for: kept.objectID)
        var deleted = 0
        for row in rows where row !== kept && row.id != kept.id {
            switch zones.answer(for: row.objectID) {
            case .notSent: break
            case .zone(let zone): guard keptZone == .zone(zone) else { continue }
            case .noAnswer: continue
            }
            context.delete(row)
            deleted += 1
        }
        return deleted
    }

    /// The copy made first, given the newest copy's values when they differ.
    /// `now` stamps that change; nil keeps the newest copy's `modifiedAt`.
    @discardableResult
    static func carryNewest(_ rows: [CDTimetableBooking], now: Date?) -> CDTimetableBooking? {
        guard let kept = rows.min(by: madeFirst) else { return nil }
        guard rows.count > 1, let newest = CDTimetableBooking.newest(of: rows), newest !== kept,
              !sameValues(kept, newest) else { return kept }
        kept.day = newest.day
        kept.halfRaw = newest.halfRaw
        kept.minute = newest.minute
        kept.order = newest.order
        kept._studentIDsData = newest._studentIDsData
        kept.sourceModifiedAt = newest.sourceModifiedAt
        kept.modifiedAt = now ?? newest.modifiedAt
        return kept
    }

    /// Made first by `createdAt` to the millisecond, as iCloud keeps it, then
    /// the lower `id`: the same answer on every device.
    static func madeFirst(_ lhs: CDTimetableBooking, _ rhs: CDTimetableBooking) -> Bool {
        let left = DataCleanupService.millisecondKey(lhs.createdAt) ?? .max
        let right = DataCleanupService.millisecondKey(rhs.createdAt) ?? .max
        if left != right { return left < right }
        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
    }

    // MARK: - Steps

    /// Every booking in the guide's store (the private store on a device with two).
    private static func bookings(in context: NSManagedObjectContext) -> [CDTimetableBooking] {
        let request = CDFetchRequest(CDTimetableBooking.self)
        if let store = RestockService.destinationStore(for: .leadGuide, in: context) {
            request.affectedStores = [store]
        }
        return context.safeFetch(request).filter { !$0.isDeleted }
    }

    /// The presentations this device has among `keys` (upper-cased IDs), by key.
    private static func presentations(
        _ keys: Set<String>, in context: NSManagedObjectContext
    ) -> [String: CDLessonAssignment] {
        let ids = keys.compactMap(UUID.init(uuidString:))
        guard !ids.isEmpty else { return [:] }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id IN %@", ids)
        var found: [String: CDLessonAssignment] = [:]
        for presentation in context.safeFetch(request) {
            guard let id = presentation.id else { continue }
            found[id.uuidString.uppercased()] = presentation
        }
        return found
    }

    private static func insert(
        _ plan: ScheduleLessonPlan.Planned, in context: NSManagedObjectContext, now: Date
    ) {
        let booking = CDTimetableBooking(context: context)
        TimetableService.assignToGuideStore(booking, in: context)
        booking.presentationID = plan.id.uuidString
        booking.createdAt = now
        set(booking, to: plan, now: now)
    }

    private static func set(_ booking: CDTimetableBooking, to plan: ScheduleLessonPlan.Planned, now: Date) {
        booking.day = plan.day
        booking.half = plan.half
        booking.setMinute = plan.minute
        booking.order = Int64(plan.order)
        booking.studentIDs = plan.presentation.studentIDs
        booking.sourceModifiedAt = plan.presentation.modifiedAt
        booking.modifiedAt = now
    }

    /// Whether `booking` already says what `plan` says.
    private static func matches(
        _ booking: CDTimetableBooking, _ plan: ScheduleLessonPlan.Planned, calendar: Calendar
    ) -> Bool {
        guard let day = booking.day, calendar.isDate(day, inSameDayAs: plan.day) else { return false }
        return booking.half == plan.half && booking.setMinute == plan.minute && Int(booking.order) == plan.order
            && booking.studentIDs == plan.presentation.studentIDs
    }

    private static func sameValues(_ lhs: CDTimetableBooking, _ rhs: CDTimetableBooking) -> Bool {
        lhs.day == rhs.day && lhs.halfRaw == rhs.halfRaw && lhs.minute == rhs.minute && lhs.order == rhs.order
            && lhs.studentIDs == rhs.studentIDs && millis(lhs.sourceModifiedAt) == millis(rhs.sourceModifiedAt)
    }

    /// A date to the millisecond, as iCloud keeps it; nil is the earliest.
    static func millis(_ date: Date?) -> Int64 {
        DataCleanupService.millisecondKey(date) ?? .min
    }
}
