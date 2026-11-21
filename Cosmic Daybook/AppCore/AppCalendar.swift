import Foundation
import CoreData
import os

/// Canonical calendar utilities for day-boundary normalization across the app.
/// Use these helpers instead of `Calendar.current` directly to avoid mismatches
/// between Planning, Today, and Agenda screens.
nonisolated enum AppCalendar {
    /// Shared calendar used for all date normalization: Gregorian, in the
    /// classroom's time zone when the guide has set one (`ClassroomCalendar`,
    /// schema 25), so a device in another zone reads the class's days as the
    /// class does (domain-logic review A4). Until one is set, and before the
    /// store has opened, it is the device's zone, `autoupdatingCurrent`, so it
    /// follows a device time-zone change by itself.
    ///
    /// Read it each time it is needed rather than keeping a copy: the zone
    /// arrives with the store, and a kept copy would stay in the old one.
    ///
    /// Note: unlike `Calendar.current`, this calendar carries no locale, so use
    /// `Calendar.current` (or a `DateFormatter`) for locale symbols such as
    /// `shortMonthSymbols`; `firstWeekday` and day arithmetic are identical.
    static var shared: Calendar {
        #if DEBUG
        if let pinnedForTesting { return pinnedForTesting }
        #endif
        return ClassroomCalendar.calendar
    }

    #if DEBUG
    /// A test's own calendar for the task it runs in, so a test of another
    /// zone never moves the zone under the tests running beside it.
    @TaskLocal static var pinnedForTesting: Calendar?
    #endif

    /// The app's Gregorian calendar in the zone `identifier` names. Nil, or an
    /// identifier `TimeZone(identifier:)` doesn't know (it is case-sensitive:
    /// "america/new_york" isn't one), is the device's own zone.
    static func calendar(inZone identifier: String?) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = identifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        return cal
    }

    // MARK: - Canonical helpers

    /// Returns the start of day in the app's time zone for the given date.
    nonisolated static func startOfDay(_ date: Date) -> Date {
        shared.startOfDay(for: date)
    }

    /// Returns the half-open range [startOfDay(date), start of the next day)
    /// used for all day-bound queries.
    nonisolated static func dayRange(for date: Date) -> (start: Date, end: Date) {
        let calendar = shared
        let start = calendar.startOfDay(for: date)
        return (start, dayStart(after: start, calendar: calendar))
    }

    /// The start of the day after `day`. Where the clocks go forward at
    /// midnight a day starts at 1:00, and a day added to that lands at 1:00
    /// the next day, an hour into it; so the start is taken again.
    nonisolated static func dayStart(after day: Date, calendar: Calendar = shared) -> Date {
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return calendar.startOfDay(for: next)
    }

    /// Matches records whose `key` falls within `day`, the way days off are
    /// matched, rather than at its exact midnight: a day saved an instant off
    /// (an older build, the clocks changing) still reads as that day.
    nonisolated static func dayPredicate(_ key: String = "date", on day: Date) -> NSPredicate {
        let range = dayRange(for: day)
        return NSPredicate(format: "%K >= %@ AND %K < %@", key, range.start as NSDate, key, range.end as NSDate)
    }

    /// True if two dates are in the same day (the app's time zone).
    nonisolated static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        shared.isDate(a, inSameDayAs: b)
    }

    /// Adds whole days to a date using the shared calendar. A day start stays
    /// a day start (`dayStart(after:)`).
    nonisolated static func addingDays(_ days: Int, to date: Date) -> Date {
        let calendar = shared
        let moved = calendar.date(byAdding: .day, value: days, to: date) ?? date
        return date == calendar.startOfDay(for: date) ? calendar.startOfDay(for: moved) : moved
    }

    /// Stable identifier for a day bucket (start-of-day epoch seconds).
    /// Useful for `id:` values in `ForEach` when you want day-identity rather than full timestamps.
    nonisolated static func dayID(_ day: Date) -> String {
        let start = startOfDay(day)
        return "day_\(Int(start.timeIntervalSince1970))"
    }
}

/// The classroom's own calendar facts, as the shared settings row carries
/// them (schema 25): its time zone, which `AppCalendar.shared` is pinned to,
/// and the school session's first and last days, which the school year's
/// start reads (`SchoolYear.currentStart`). One copy for the process, behind a
/// lock, because `AppCalendar` is read from every isolation and has no store
/// to ask. `ClassroomCalendarFollower` keeps it matching the live class's
/// row; nothing else writes it, so tests and the Sample Class leave it as the
/// device's zone with no session.
nonisolated enum ClassroomCalendar {

    struct Snapshot: Equatable, Sendable {
        /// A `TimeZone` identifier, as stored; nil or unknown is the device's zone.
        var timeZoneID: String?
        var session: SchoolSession?
    }

    private struct State: Sendable {
        var snapshot = Snapshot()
        var calendar = AppCalendar.calendar(inZone: nil)
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// The app's calendar as it stands (`AppCalendar.shared`).
    static var calendar: Calendar { state.withLock { $0.calendar } }

    static var current: Snapshot { state.withLock { $0.snapshot } }

    /// Takes `snapshot` as the classroom's. Returns whether it changed.
    @discardableResult
    static func adopt(_ snapshot: Snapshot) -> Bool {
        state.withLock { state in
            guard state.snapshot != snapshot else { return false }
            state.snapshot = snapshot
            state.calendar = AppCalendar.calendar(inZone: snapshot.timeZoneID)
            return true
        }
    }
}

/// Keeps `ClassroomCalendar` matching the live class's settings row: read
/// once the app's own store has opened (`CoreDataStack`), again after each
/// change iCloud brings in or a restore writes, and when this device writes
/// the row. Never from the Sample Class or a test's store: only the store
/// `follow` was given.
///
/// A change tells the rest of the app the way a day off does
/// (`.schoolDayDataDidChange`): every cached school day and day start was
/// worked out in the old zone or session.
@MainActor
enum ClassroomCalendarFollower {
    private static weak var liveCoordinator: NSPersistentStoreCoordinator?
    private static weak var liveContext: NSManagedObjectContext?
    private static var watching: [Task<Void, Never>] = []
    private static var settling: Task<Void, Never>?

    /// How long after iCloud writes to the store the row is read: the view
    /// context takes the change in a moment later, and until then a fetch
    /// still shows the row it already holds.
    static let settleDelay: Duration = .milliseconds(750)

    /// Follows `container`, the app's own notebook or the assistant's class.
    static func follow(_ container: NSPersistentContainer) {
        let coordinator = container.persistentStoreCoordinator
        liveCoordinator = coordinator
        liveContext = container.viewContext
        refresh(from: container.viewContext)
        watching.forEach { $0.cancel() }
        watching = [
            // iCloud wrote to the store: read once the burst's first change has settled.
            Task {
                let changes = NotificationCenter.default
                    .notifications(named: .NSPersistentStoreRemoteChange, object: coordinator)
                    .map { _ in () }
                for await _ in changes { refreshAfterSettling() }
            },
            // A restore, or anything else here that says the school calendar
            // changed. Our own post lands here too and finds nothing new.
            Task {
                let changes = NotificationCenter.default
                    .notifications(named: .schoolDayDataDidChange)
                    .map { _ in () }
                for await _ in changes {
                    if let liveContext { refresh(from: liveContext) }
                }
            }
        ]
    }

    /// One read a moment from now, however many changes arrive meanwhile.
    private static func refreshAfterSettling() {
        guard settling == nil else { return }
        settling = Task {
            try? await Task.sleep(for: settleDelay)
            settling = nil
            if let liveContext { refresh(from: liveContext) }
        }
    }

    /// Reads the row again, when `context` is the followed store's. Returns
    /// whether the classroom's calendar changed.
    @discardableResult
    static func refresh(from context: NSManagedObjectContext) -> Bool {
        guard let coordinator = context.persistentStoreCoordinator, coordinator === liveCoordinator else {
            return false
        }
        guard ClassroomCalendar.adopt(AttendanceEmailLog.classroomCalendar(in: context)) else { return false }
        NotificationCenter.default.post(name: .schoolDayDataDidChange, object: nil)
        return true
    }
}
