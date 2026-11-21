import Foundation
import CoreData

// MARK: - Aging Types
enum AgingBucket: Int, Codable, Comparable, Sendable {
    case fresh = 0
    case aging = 1
    case stale = 2

    static func < (lhs: AgingBucket, rhs: AgingBucket) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct AgingPolicy {
    /// First bucket boundary where items start to be considered aging.
    static let agingDays: Int = 5

    /// School days of silence after which work counts as stale.
    ///
    /// The single stale threshold in the app. It decides the card's colour
    /// indicator, the Today screen's stale list, the lesson list's warning, the
    /// Checklist's "needs a check-in" dot, and, through
    /// `LessonsAndWorkTriage.staleSchoolDays`, whether work lands in the
    /// Attention list. These used to be 9 here and 10 in the triage rule, and
    /// 14 weekdays on the Checklist, so a card could look stale without being
    /// asked for.
    static let staleDays: Int = 10
}

// MARK: - Work Neglect
/// How long open work has gone without the guide: the one clock (domain logic
/// review 2026-11-20, R13). School days since the latest meaningful touch.
///
/// Triage, Today's Gone quiet, the work card's age bar, the Checklist's dot
/// and the meeting's stuck list all read it. Before, the Checklist counted
/// weekdays from `lastTouchedAt` and never saw a check-in or a note, the
/// meetings counted calendar days since the work was made, and none of them
/// knew a rest had ended: work set aside for a month woke up as a month
/// untouched.
enum WorkNeglect {
    /// The most recent meaningful touch of a work model, as a start of day:
    /// the latest of
    /// - `lastTouchedAt`, when set,
    /// - its latest completed check-in on or before today (Record Practice
    ///   makes one),
    /// - its latest note (edited or written),
    /// - `completedAt`,
    /// - the day a rest ended (`restingUntil`, once it has come): setting work
    ///   aside is a plan, so the clock starts again when the plan runs out;
    /// and when there is none of these, `assignedAt`, then `createdAt`.
    ///
    /// These used to be taken in that order rather than by date, so a
    /// check-in from months ago hid yesterday's note and the work read as
    /// stale the day after the guide wrote about it.
    ///
    /// - Parameter cutoff: when given, only touches before that day count: a
    ///   meeting reads the work it has just decided on as it stood before
    ///   the meeting's own log touched it.
    nonisolated static func lastMeaningfulTouchDate(
        for work: CDWorkModel,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil,
        asOf now: Date = Date(),
        before cutoff: Date? = nil
    ) -> Date {
        let today = AppCalendar.startOfDay(now)
        let counts = { (day: Date) in day <= today && (cutoff.map { day < $0 } ?? true) }
        let touches = [lastSeen(for: work, checkIns: checkIns, notes: notes, asOf: now, before: cutoff),
                       work.completedAt.map(AppCalendar.startOfDay).flatMap { counts($0) ? $0 : nil },
                       work.restingUntil.map(AppCalendar.startOfDay).flatMap { counts($0) ? $0 : nil }]
        if let latest = touches.compactMap({ $0 }).max() { return latest }
        return AppCalendar.startOfDay(work.assignedAt ?? work.createdAt ?? now)
    }

    /// The last day the guide looked at the work, as a start of day: a log
    /// (`lastTouchedAt`), a completed check-in on or before today, or a note.
    /// Nil when nobody has yet. Unlike `lastMeaningfulTouchDate` this never
    /// falls back to the day the work was made, and a rest ending isn't
    /// someone looking: triage asks it whether a due date that has come has
    /// been seen since.
    nonisolated static func lastSeen(
        for work: CDWorkModel,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil,
        asOf now: Date = Date(),
        before cutoff: Date? = nil
    ) -> Date? {
        let today = AppCalendar.startOfDay(now)
        let isBeforeCutoff = { (day: Date) in cutoff.map { day < $0 } ?? true }

        let workCheckIns = checkIns ?? ((work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? [])
        let latestCheckIn: Date? = workCheckIns
            .filter { $0.status == .completed }
            .compactMap { $0.date.map(AppCalendar.startOfDay) }
            .filter { $0 <= today && isBeforeCutoff($0) }
            .max()

        let workNotes = notes ?? ((work.unifiedNotes?.allObjects as? [CDNote]) ?? [])
        let latestNote: Date? = workNotes
            .compactMap { note in [note.updatedAt, note.createdAt].compactMap { $0 }.max() }
            .map(AppCalendar.startOfDay)
            .filter(isBeforeCutoff)
            .max()

        let logged = work.lastTouchedAt.map(AppCalendar.startOfDay).flatMap { isBeforeCutoff($0) ? $0 : nil }
        return [logged, latestCheckIn, latestNote].compactMap { $0 }.max()
    }

    /// School days between the last meaningful touch and `now`'s day.
    /// This is the authoritative version for business rules.
    nonisolated static func daysSinceLastTouch(
        for work: CDWorkModel,
        using context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil,
        asOf now: Date = Date(),
        before cutoff: Date? = nil
    ) -> Int {
        // Clamped to the school-year counter epoch so work that was last touched in a previous
        // year ages from the first day of this one instead of arriving stale on day one.
        let last = SchoolYearCounters.countFrom(
            lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: notes, asOf: now, before: cutoff)
        )
        return SchoolDayChecker.schoolDaysBetween(start: last, end: AppCalendar.startOfDay(now), using: context)
    }

    /// Maps day difference to an AgingBucket using school days.
    /// Returns `.fresh` while work is intentionally resting.
    nonisolated static func agingBucket(
        for work: CDWorkModel,
        using context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil,
        asOf now: Date = Date()
    ) -> AgingBucket {
        if work.isResting(asOf: now) { return .fresh }
        let days = daysSinceLastTouch(for: work, using: context, checkIns: checkIns, notes: notes, asOf: now)
        if days >= AgingPolicy.staleDays { return .stale }
        if days >= AgingPolicy.agingDays { return .aging }
        return .fresh
    }

    /// Whether the work has gone quiet: `AgingPolicy.staleDays` school days or
    /// more since its last touch, and not resting.
    nonisolated static func isStale(
        _ work: CDWorkModel,
        using context: NSManagedObjectContext,
        checkIns: [CDWorkCheckIn]? = nil,
        notes: [CDNote]? = nil,
        asOf now: Date = Date()
    ) -> Bool {
        agingBucket(for: work, using: context, checkIns: checkIns, notes: notes, asOf: now) == .stale
    }

    // MARK: - For the main actor's screens

    /// `daysSinceLastTouch` through the app's school-day cache
    /// (`SchoolCalendarService`, which triage counts with too): the plain
    /// counter asks the store about each day, which is too much for a grid of
    /// cells or a view's body. Same clamp to the school year, same answer.
    static func quietDays(
        for work: CDWorkModel,
        using context: NSManagedObjectContext,
        asOf now: Date = Date(),
        before cutoff: Date? = nil
    ) -> Int {
        let last = lastMeaningfulTouchDate(for: work, asOf: now, before: cutoff)
        return SchoolCalendarService.shared.schoolDaysSinceCreation(createdAt: last, asOf: now, using: context)
    }

    /// Whether the work has gone `threshold` school days or more without a
    /// touch, and isn't resting: the Checklist's dot (`AgingPolicy.staleDays`)
    /// and a meeting's "stuck" (the guide's own Work Age setting).
    static func hasGoneQuiet(
        _ work: CDWorkModel,
        for threshold: Int,
        using context: NSManagedObjectContext,
        asOf now: Date = Date()
    ) -> Bool {
        guard !work.isResting(asOf: now) else { return false }
        return quietDays(for: work, using: context, asOf: now) >= threshold
    }
}
