// TimetableService.swift
// Every change to the Schedules timetables: the lanes, their weekly and
// one-off blocks, and one day's changes. The notebook's page and MCP write
// through here; the Daybook Assistant only reads. Block edits are in
// +Blocks, day changes in +Days.
//
// Like RestockService it changes objects and leaves saving to the caller,
// which saves on the view context: new rows go into the private store, and
// `SharedStoreOrphanGuard`, which watches only view-context saves, puts them
// into the classroom share.

import CoreData
import Foundation

/// The one writer for `CDTimetableLane`, `CDTimetableBlock` and
/// `CDTimetableChange`. Only the guide's devices write them.
///
/// - **Weeks already past stay as they were.** This Day and After ends a
///   block the day before and starts a copy with the new values that day;
///   deleting a weekly block ends it rather than erasing it.
/// - **Only This Day** is a `CDTimetableChange` for that date: "changed" with
///   the values in full, or "cancelled". Out Today is an "out" change on a
///   person lane. Undo deletes the day's change.
/// - **Two devices can race.** Each change for a block and day is updated in
///   every copy rather than folded, and readers take the newest
///   (`ScheduleDayResolver`), so nothing a device deletes can take another's
///   row out of the share.
enum TimetableService {

    /// How far an edit or delete of a weekly block reaches, as Calendar asks
    /// about a repeating event.
    enum EditScope: Sendable {
        /// That date only: a change for the day.
        case onlyThisDay
        /// That date and every week after; earlier weeks keep the old values.
        case thisDayAndAfter
        /// The block itself, every week. A delete ends it from today, so the
        /// weeks already past still read as they were.
        case everyWeek
    }

    /// The lanes, blocks and changes as plain values, for the resolver.
    struct Timetable: Sendable, Equatable {
        var lanes: [TimetableLaneSnapshot]
        var blocks: [TimetableBlockSnapshot]
        var changes: [TimetableChangeSnapshot]
    }

    /// The fallback name of the guide's lane, when he hasn't set one.
    static let guideLaneFallbackName = "Guide"

    // MARK: - Reading

    /// Every lane, in its order. `store` limits it to one store: the Assistant
    /// reads the classroom's from the shared store only.
    static func lanes(in context: NSManagedObjectContext, store: NSPersistentStore? = nil) -> [CDTimetableLane] {
        let request = CDFetchRequest(CDTimetableLane.self)
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)
        ]
        if let store { request.affectedStores = [store] }
        return context.safeFetch(request)
    }

    /// Every block, or one lane's.
    static func blocks(
        of lane: CDTimetableLane? = nil,
        in context: NSManagedObjectContext,
        store: NSPersistentStore? = nil
    ) -> [CDTimetableBlock] {
        let request = CDFetchRequest(CDTimetableBlock.self)
        if let lane {
            guard let id = lane.id?.uuidString else { return [] }
            request.predicate = NSPredicate(format: "laneID ==[c] %@", id)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "startMinute", ascending: true)]
        if let store { request.affectedStores = [store] }
        return context.safeFetch(request)
    }

    /// The changes from `start` through `end` (days, inclusive).
    static func changes(
        from start: Date,
        through end: Date,
        in context: NSManagedObjectContext,
        store: NSPersistentStore? = nil,
        calendar: Calendar = AppCalendar.shared
    ) -> [CDTimetableChange] {
        let first = calendar.startOfDay(for: start)
        let after = dayAfter(end, calendar: calendar)
        let request = CDFetchRequest(CDTimetableChange.self)
        request.predicate = NSPredicate(format: "day >= %@ AND day < %@", first as NSDate, after as NSDate)
        if let store { request.affectedStores = [store] }
        return context.safeFetch(request)
    }

    /// The lanes, every block, and the changes from `start` through `end`, as
    /// the resolver takes them.
    static func timetable(
        from start: Date,
        through end: Date,
        in context: NSManagedObjectContext,
        store: NSPersistentStore? = nil,
        calendar: Calendar = AppCalendar.shared
    ) -> Timetable {
        Timetable(
            lanes: lanes(in: context, store: store).compactMap(TimetableLaneSnapshot.init),
            blocks: blocks(in: context, store: store).compactMap(TimetableBlockSnapshot.init),
            changes: changes(from: start, through: end, in: context, store: store, calendar: calendar)
                .compactMap(TimetableChangeSnapshot.init)
        )
    }

    // MARK: - Lanes

    /// Makes the starter lanes on first run: our class, the adolescent room,
    /// and the guide's lane, named as he named himself
    /// (`ClassroomNames.myName`). With lanes already there it makes none and
    /// returns those.
    @discardableResult
    static func makeStarterLanes(in context: NSManagedObjectContext, now: Date = Date()) -> [CDTimetableLane] {
        let existing = lanes(in: context)
        guard existing.isEmpty else { return existing }
        let myName = ClassroomNames.myName(role: .leadGuide, in: context).trimmed()
        return [
            insertLane("Our class", kind: .room, sortOrder: 0, in: context, now: now),
            insertLane("Adolescent room", kind: .room, sortOrder: 1, in: context, now: now),
            insertLane(
                myName.isEmpty ? guideLaneFallbackName : myName, kind: .person, isGuide: true, sortOrder: 2,
                in: context, now: now
            )
        ]
    }

    /// Adds a person's lane (Morah Devora) after the others.
    @discardableResult
    static func addPerson(
        named name: String,
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) -> CDTimetableLane {
        addLane(named: name, kind: .person, in: context, now: now)
    }

    /// Adds a lane after the others.
    @discardableResult
    static func addLane(
        named name: String,
        kind: TimetableLaneKind,
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) -> CDTimetableLane {
        let next = (lanes(in: context).map(\.sortOrder).max() ?? -1) + 1
        return insertLane(name.trimmed(), kind: kind, sortOrder: next, in: context, now: now)
    }

    static func rename(_ lane: CDTimetableLane, to name: String, now: Date = Date()) {
        let name = name.trimmed()
        guard lane.name != name else { return }
        lane.name = name
        lane.modifiedAt = now
    }

    static func setColor(_ colorRaw: String, of lane: CDTimetableLane, now: Date = Date()) {
        guard lane.colorRaw != colorRaw else { return }
        lane.colorRaw = colorRaw
        lane.modifiedAt = now
    }

    /// Puts the lanes in `ordered`'s order; only those whose place changed are written.
    static func reorder(_ ordered: [CDTimetableLane], now: Date = Date()) {
        for (index, lane) in ordered.enumerated() where lane.sortOrder != Int64(index) {
            lane.sortOrder = Int64(index)
            lane.modifiedAt = now
        }
    }

    // MARK: - Shared steps

    private static func insertLane(
        _ name: String,
        kind: TimetableLaneKind,
        isGuide: Bool = false,
        sortOrder: Int64,
        in context: NSManagedObjectContext,
        now: Date
    ) -> CDTimetableLane {
        let lane = CDTimetableLane(context: context)
        assignToGuideStore(lane, in: context)
        lane.name = name
        lane.kind = kind
        lane.isGuide = isGuide
        lane.sortOrder = sortOrder
        lane.createdAt = now
        lane.modifiedAt = now
        return lane
    }

    /// New rows go into the guide's private store, from which
    /// `SharedStoreOrphanGuard` shares them once the view context saves.
    /// Nothing to choose with one store (tests, the Sample Class).
    static func assignToGuideStore(_ object: NSManagedObject, in context: NSManagedObjectContext) {
        if let store = RestockService.destinationStore(for: .leadGuide, in: context) {
            context.assign(object, to: store)
        }
    }

    /// The day after `day`, at its start: a calendar step, not 86,400 seconds.
    static func dayAfter(_ day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }

    /// The day before `day`, at its start.
    static func dayBefore(_ day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .day, value: -1, to: start) ?? start
    }
}
