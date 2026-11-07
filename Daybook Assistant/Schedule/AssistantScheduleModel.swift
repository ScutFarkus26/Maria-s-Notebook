import Foundation
import CoreData
import Observation

/// The Schedule tab: one day of the class's timetable, read from the
/// classroom share and worked out by `ScheduleDayResolver`, the notebook's
/// own rules. It only reads: the guide is the only one who changes it.
///
/// The guide's planned lessons arrive as bookings (`CDTimetableBooking`),
/// which carry the day, the half or the time, and the children, but never a
/// lesson's name, so no lesson text can reach this tab. They show as "With
/// Danny" rows with the children's short names.
@MainActor
@Observable
final class AssistantScheduleModel {

    /// The day shown (start of day).
    private(set) var day: Date
    /// The day as the resolver worked it out; nil before the first load.
    private(set) var resolved: ScheduleDay?
    /// "Monday, October 26 · 15 Cheshvan · Vayera".
    private(set) var headerLine = ""
    /// Why the day has no school, when it hasn't.
    private(set) var dayOff: AssistantAttendanceViewModel.DayOff?
    /// The lanes the switcher offers, in order.
    private(set) var laneOptions: [AssistantScheduleRows.LaneOption] = []
    /// The schedule shown, or nil for every lane at once. The tab always
    /// shows one once there are lanes (`settleLane`); nil is the whole day
    /// as the resolver worked it out.
    var laneFilter: UUID?
    /// The time the Now card reads: moved on each minute while the tab shows
    /// (`AssistantScheduleView.followClock`) and on a return to the app
    /// (`ScheduleFollowsScene`). Only the Now card's own view reads it.
    var clock = Date()
    /// Children's short names ("Maya S") by upper-cased student ID.
    private(set) var childNames: [String: String] = [:]
    /// Reloads the tab when the guide's changes arrive from iCloud.
    @ObservationIgnored private(set) var importReloader: RemoteImportReloader?

    let context: NSManagedObjectContext
    /// The time now; tests fix it.
    let now: () -> Date
    private let currentGuideName: @MainActor () -> String?
    private let calendar: Calendar

    /// - Parameter guideName: the guide's name as her screens show it
    ///   (`AssistantBootstrapper.guideNameToShow`); nil reads "Your guide".
    init(
        context: NSManagedObjectContext,
        guideName: @escaping @MainActor () -> String? = { nil },
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = AppCalendar.shared
    ) {
        self.context = context
        self.currentGuideName = guideName
        self.now = now
        self.calendar = calendar
        self.day = calendar.startOfDay(for: now())
        self.importReloader = RemoteImportReloader { [weak self] in self?.load() }
    }

    // MARK: - What the tab shows

    /// The guide's name, or "Your guide". Read again on every load, so a
    /// name that arrives later counts.
    private(set) var guideName = AssistantScheduleRows.guideFallbackName

    var isToday: Bool { calendar.isDate(day, inSameDayAs: now()) }

    /// Whether the guide has set up any lanes yet.
    var hasLanes: Bool { !(resolved?.lanes.isEmpty ?? true) }

    /// The day's rows in time order, for the lane filter's choice.
    var rows: [AssistantScheduleRows.Row] {
        guard let resolved else { return [] }
        return AssistantScheduleRows.rows(for: resolved, lane: laneFilter, names: names)
    }

    /// "1 change today", when the guide changed the day.
    var changedLine: String? {
        resolved.flatMap { AssistantScheduleRows.changedLine(for: $0, isToday: isToday) }
    }

    /// "Morah Devora is out.", for each person out that day.
    var outLines: [String] {
        resolved.map { AssistantScheduleRows.outLines(for: $0, names: names) } ?? []
    }

    /// Who is where at `date`, on today only.
    func nowCard(at date: Date) -> AssistantScheduleRows.NowCard? {
        guard let resolved, resolved.isSchoolDay, calendar.isDate(day, inSameDayAs: date) else { return nil }
        return AssistantScheduleRows.nowCard(
            for: resolved, minute: TimetableDay.minute(of: date, calendar: calendar), names: names, lane: laneFilter
        )
    }

    /// One schedule at a time: keeps the one shown while the guide still has
    /// it, else the one last chosen on this phone, else the first.
    func settleLane(preferring remembered: UUID?) {
        let ids = laneOptions.map(\.id)
        if let laneFilter, ids.contains(laneFilter) { return }
        let lane = remembered.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
        if laneFilter != lane { laneFilter = lane }
    }

    var names: AssistantScheduleRows.Names {
        AssistantScheduleRows.Names(guideName: guideName, children: childNames)
    }

    // MARK: - Loading

    /// Reads the lanes, the blocks, the day's changes and bookings, the
    /// children and the school day again, from the classroom share only,
    /// and works out the day.
    func load() {
        let store = self.store
        let start = calendar.startOfDay(for: day)
        let after = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)

        let lanes = fetch(CDTimetableLane.self, store: store).compactMap(TimetableLaneSnapshot.init)
        let onTheDay = Self.blocks(on: start, before: after, calendar: calendar)
        let blocks = fetch(CDTimetableBlock.self, predicate: onTheDay, store: store)
            .compactMap(TimetableBlockSnapshot.init)
        let dayRange = NSPredicate(format: "day >= %@ AND day < %@", start as NSDate, after as NSDate)
        let changes = fetch(CDTimetableChange.self, predicate: dayRange, store: store)
            .compactMap(TimetableChangeSnapshot.init)
        // Two devices may each have written one for a lesson: the newest counts.
        let bookings = CDTimetableBooking.newestPerPresentation(
            fetch(CDTimetableBooking.self, predicate: dayRange, store: store)
        )
        let lessons = bookings.compactMap(ScheduleLessonSnapshot.init(booking:))

        var levels: [String: CDStudent.Level] = [:]
        var shortNames: [String: String] = [:]
        for student in fetch(CDStudent.self, store: store) {
            guard let id = student.id?.uuidString.uppercased() else { continue }
            levels[id] = student.level
            shortNames[id] = student.shortName
        }
        if childNames != shortNames { childNames = shortNames }
        let name = currentGuideName()?.trimmed() ?? ""
        let guide = name.isEmpty ? AssistantScheduleRows.guideFallbackName : name
        if guideName != guide { guideName = guide }

        let off = AssistantAttendanceViewModel.dayOff(on: start, in: context)
        if dayOff != off { dayOff = off }
        let newDay = ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
            day: start, lanes: lanes, blocks: blocks, changes: changes, lessons: lessons,
            studentLevels: levels, isSchoolDay: off == nil, calendar: calendar
        ))
        if resolved != newDay { resolved = newDay }

        let options = newDay.lanes.enumerated().map { index, lane in
            AssistantScheduleRows.LaneOption(
                id: lane.id, name: AssistantScheduleRows.name(of: lane.lane, guideName: guide),
                colorRaw: lane.lane.colorRaw, index: index
            )
        }
        if laneOptions != options { laneOptions = options }
        // A lane the guide removed: the tab picks another (`settleLane`).
        if let laneFilter, !options.contains(where: { $0.id == laneFilter }) { self.laneFilter = nil }
        let header = HebrewDateText.headerLine(for: start, calendar: calendar)
        if headerLine != header { headerLine = header }
    }

    /// Shows `date`'s day.
    func show(_ date: Date) {
        day = calendar.startOfDay(for: date)
        load()
    }

    /// Back to today.
    func showToday() { show(now()) }

    /// The calendar day (its start) the tab was last on screen; nil before
    /// it first shows.
    @ObservationIgnored private(set) var seenOn: Date?

    /// The tab shows again (on appear, or the app's return while it's on
    /// screen): after a night away, today, whatever day was left on screen,
    /// as Attendance does; within the day, the day she left, loaded again.
    /// Only the tab's own scene-phase handler used to move it to today, and
    /// that doesn't hear a return while another tab shows (bug hunt
    /// 2026-11-06 #14).
    func reloadAfterAway() {
        let today = calendar.startOfDay(for: now())
        defer { seenOn = today }
        if let seenOn, seenOn != today { day = today }
        load()
    }

    /// The minute's turn while the tab shows: the Now card's clock moves on,
    /// and past midnight a tab left on today moves to the new today. A day
    /// she stepped to stays. Before, the stepper went on saying "Today" with
    /// yesterday's date and the Now card went blank (bug hunt 2026-11-06 #18).
    func minuteTurned() {
        let date = now()
        clock = date
        let today = calendar.startOfDay(for: date)
        guard let seenOn, seenOn != today else { return }
        self.seenOn = today
        if day == seenOn { show(today) }
    }

    /// The school day before or after the one shown: a weekend or a day off
    /// is skipped, up to two weeks of them.
    func step(forward: Bool) {
        var next = day
        for _ in 0..<14 {
            next = calendar.date(byAdding: .day, value: forward ? 1 : -1, to: next) ?? next
            if AssistantAttendanceViewModel.dayOff(on: next, in: context) == nil {
                show(next)
                return
            }
        }
        show(calendar.date(byAdding: .day, value: forward ? 1 : -1, to: day) ?? day)
    }

    // MARK: - Reading

    /// The classroom share's store. Nil with one store (the sample class,
    /// tests), which holds only the class. An Apple Account that keeps a
    /// notebook of its own has that notebook's schedule in the private store,
    /// which isn't this class's.
    var store: NSPersistentStore? {
        context.persistentStoreCoordinator?.persistentStores.first {
            $0.configurationName == CoreDataStack.sharedConfiguration
        }
    }

    /// The blocks that can be on the day starting `start`, as the resolver
    /// keeps them (`ScheduleDayResolver.applies`): a one-off on that day, or
    /// a weekly block on its weekday. Every block in the store used to be
    /// fetched, its children's list decoded, and all but the day's dropped
    /// (bug hunt 2026-11-03 #27). The resolver still checks each one.
    static func blocks(on start: Date, before after: Date, calendar: Calendar) -> NSPredicate {
        let oneOff = NSPredicate(format: "onDay >= %@ AND onDay < %@", start as NSDate, after as NSDate)
        guard let weekday = TimetableDay.weekday(of: start, calendar: calendar) else { return oneOff }
        let weekly = NSPredicate(format: "onDay == nil AND weekdayRaw == %@", weekday.rawValue)
        return NSCompoundPredicate(orPredicateWithSubpredicates: [oneOff, weekly])
    }

    private func fetch<T: NSManagedObject>(
        _ type: T.Type, predicate: NSPredicate? = nil, store: NSPersistentStore?
    ) -> [T] {
        let request = CDFetchRequest(type)
        request.predicate = predicate
        if let store { request.affectedStores = [store] }
        return context.safeFetch(request)
    }
}

// MARK: - Following imports and the app

extension AssistantScheduleModel {

    /// Reloads the tab whenever an import into the classroom's store
    /// finishes, until the calling task is cancelled.
    func followRemoteImports(into storeIdentifier: String) async {
        await importReloader?.observeImports(into: storeIdentifier)
    }

    /// The app left the screen (`isActive` false) or came back to it. Away,
    /// an import doesn't reload the tab; back, the return's own `load()`
    /// shows it.
    func followScene(isActive: Bool) {
        if isActive {
            importReloader?.appReturned()
        } else {
            importReloader?.appLeft()
        }
    }
}
