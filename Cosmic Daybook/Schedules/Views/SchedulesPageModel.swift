// SchedulesPageModel.swift
// What the Schedules page shows and the edits it makes. It reads the lanes,
// blocks and changes (`TimetableService`), the guide's planned lessons with
// their names (`ScheduleLessonPlan`) and the school calendar, and works out
// each day once (`ScheduleDayResolver`). Every edit goes through
// `TimetableService` and is saved on the view context, so
// `SharedStoreOrphanGuard` shares new rows; a failed save raises the app's
// plain save alert (`SaveCoordinator`).

import Combine
import CoreData
import Foundation

@Observable
final class SchedulesPageModel {

    enum Mode: String, CaseIterable, Identifiable {
        case day
        case week

        var id: String { rawValue }

        var label: String {
            switch self {
            case .day: "Day"
            case .week: "Week"
            }
        }
    }

    /// One school day of the Week view.
    struct WeekColumn: Identifiable, Equatable {
        let day: Date
        let resolved: ScheduleDay

        var id: Date { day }
    }

    /// A lane as the Lanes sheet leaves it: its name and color, in the order given.
    struct LaneEdit: Identifiable, Equatable {
        let id: UUID
        var name: String
        var colorRaw: String
        let kind: TimetableLaneKind
        let isGuide: Bool
    }

    @ObservationIgnored let context: NSManagedObjectContext
    @ObservationIgnored let saveCoordinator: SaveCoordinator
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private(set) var reloadTask: Task<Void, Never>?
    /// How many times `reload()` has run (for tests).
    @ObservationIgnored private(set) var reloadCount = 0

    /// The day shown (start of day); in the Week view, the week it falls in.
    var day: Date {
        didSet {
            let start = calendar.startOfDay(for: day)
            if day != start {
                day = start
                return
            }
            if day != oldValue { reload() }
        }
    }

    var mode: Mode = .day {
        didSet { if mode != oldValue { reload() } }
    }

    /// The lane the Week view shows; nil is the first.
    var weekLaneID: UUID?

    /// Children's short names by upper-cased student ID, for warnings and rows.
    var studentNames: [String: String] = [:]

    private(set) var lanes: [TimetableLaneSnapshot] = []
    private(set) var resolved: ScheduleDay
    /// The Week view's school days; empty in the Day view.
    private(set) var week: [WeekColumn] = []

    init(
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator,
        day: Date = Date(),
        calendar: Calendar = AppCalendar.shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.saveCoordinator = saveCoordinator
        self.calendar = calendar
        self.now = now
        let start = calendar.startOfDay(for: day)
        self.day = start
        self.resolved = ScheduleDay(day: start, isSchoolDay: true, lanes: [], changeCount: 0, warnings: [])
    }

    // MARK: - Reading

    var hasLanes: Bool { !lanes.isEmpty }

    var isToday: Bool { calendar.isDate(day, inSameDayAs: now()) }

    func isToday(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: now()) }

    /// Minutes after midnight now, for the now line.
    func nowMinute(at date: Date) -> Int { TimetableDay.minute(of: date, calendar: calendar) }

    var lanesByID: [UUID: TimetableLaneSnapshot] {
        Dictionary(lanes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Lanes whose blocks are typed here: every lane but the guide's, which
    /// reads his planned lessons instead.
    var editableLanes: [TimetableLaneSnapshot] {
        lanes.filter { !($0.kind == .person && $0.isGuide) }
    }

    var personLanes: [TimetableLaneSnapshot] { lanes.filter { $0.kind == .person } }

    var weekLane: TimetableLaneSnapshot? {
        lanes.first { $0.id == weekLaneID } ?? lanes.first
    }

    func name(ofStudent id: String) -> String? { studentNames[id.uppercased()] }

    /// The day's warnings, as the page words them.
    var warningLines: [(warning: ScheduleDay.Warning, text: String)] {
        resolved.warnings.map { ($0, $0.text(name: name(ofStudent:))) }
    }

    func reload() {
        reloadCount += 1
        let weekDays = Self.weekDays(containing: day, calendar: calendar)
        let first = weekDays.first ?? day
        let last = weekDays.last ?? day
        let timetable = TimetableService.timetable(from: first, through: last, in: context, calendar: calendar)
        lanes = timetable.lanes
        let nonSchool = SchoolDayChecker.nonSchoolDaySet(
            in: first..<TimetableService.dayAfter(last, calendar: calendar), using: context, calendar: calendar
        )
        let levels = ScheduleLessonPlan.studentLevels(in: context)
        resolved = resolve(day, timetable: timetable, nonSchool: nonSchool, levels: levels)
        guard mode == .week else {
            week = []
            return
        }
        week = Self.schoolDays(of: weekDays, nonSchool: nonSchool, calendar: calendar).map {
            WeekColumn(day: $0, resolved: resolve($0, timetable: timetable, nonSchool: nonSchool, levels: levels))
        }
    }

    /// A save elsewhere touched what the page reads: reload after a beat.
    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.reload()
        }
    }

    private func resolve(
        _ day: Date,
        timetable: TimetableService.Timetable,
        nonSchool: Set<Date>,
        levels: [String: CDStudent.Level]
    ) -> ScheduleDay {
        let isSchoolDay = !nonSchool.contains(calendar.startOfDay(for: day))
        return ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
            day: day, lanes: timetable.lanes, blocks: timetable.blocks, changes: timetable.changes,
            lessons: isSchoolDay ? ScheduleLessonPlan.lessons(on: day, in: context, calendar: calendar) : [],
            studentLevels: levels, isSchoolDay: isSchoolDay, calendar: calendar
        ))
    }

    // MARK: - Weeks

    /// The seven days of the week `day` falls in, in the calendar's order.
    static func weekDays(containing day: Date, calendar: Calendar) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            .map(calendar.startOfDay(for:))
    }

    /// The Week view's columns: Monday to Friday, and a weekend day only when
    /// the school calendar makes it a school day. A weekday off stays, and
    /// reads "No school".
    static func schoolDays(of days: [Date], nonSchool: Set<Date>, calendar: Calendar) -> [Date] {
        days.filter { day in
            let weekday = calendar.component(.weekday, from: day)
            return (2...6).contains(weekday) || !nonSchool.contains(calendar.startOfDay(for: day))
        }
    }

    // MARK: - Moving

    /// A day, or a week in the Week view, back (-1) or on (1).
    func step(_ direction: Int) {
        let days = mode == .week ? 7 * direction : direction
        day = calendar.date(byAdding: .day, value: days, to: day) ?? day
    }

    func goToToday() { day = calendar.startOfDay(for: now()) }

    // MARK: - Following edits elsewhere

    /// What the page reads: a save touching one of these, on any context
    /// (another window, MCP, a CloudKit import), reloads it.
    nonisolated static let inputEntities: Set<String> = [
        "TimetableLane", "TimetableBlock", "TimetableChange", "LessonAssignment",
        "NonSchoolDay", "SchoolDayOverride", "Student"
    ]

    nonisolated static func inputChanges() -> some Publisher<Void, Never> {
        let entities = inputEntities
        return NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            // @Sendable: runs on the saving context's queue.
            .filter { @Sendable note in ManagedObjectChangeScope.saveTouches(entities, in: note.userInfo) }
            .map { @Sendable _ in () }
            .receive(on: RunLoop.main)
    }
}
