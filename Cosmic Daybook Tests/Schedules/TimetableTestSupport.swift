import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Shared by the Schedules suites: days built at noon in the app's calendar
/// (safe in any time zone), four lanes, and three children.
@MainActor
enum TimetableTestSupport {
    static let calendar = AppCalendar.shared

    /// The start of `year-month-day` in the app's calendar.
    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return calendar.startOfDay(for: noon)
    }

    /// `date` at `hour:minute`.
    static func time(_ date: Date, _ hour: Int, _ minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: second, of: date)!
    }

    static func minutes(_ hour: Int, _ minute: Int = 0) -> Int {
        hour * 60 + minute
    }

    // Monday 26 October 2026 and the days around it.
    static let monday = day(2026, 10, 26)
    static let tuesday = day(2026, 10, 27)
    static let wednesday = day(2026, 10, 28)
    static let friday = day(2026, 10, 30)
    static let lastMonday = day(2026, 10, 19)
    static let nextMonday = day(2026, 11, 2)

    // The lanes.
    static let ourClass = TimetableLaneSnapshot(name: "Our class", kind: .room, sortOrder: 0)
    static let adolescentRoom = TimetableLaneSnapshot(name: "Adolescent room", kind: .room, sortOrder: 1)
    static let guide = TimetableLaneSnapshot(name: "Danny", kind: .person, isGuide: true, sortOrder: 2)
    static let devora = TimetableLaneSnapshot(name: "Morah Devora", kind: .person, sortOrder: 3)
    static let lanes = [devora, guide, ourClass, adolescentRoom]

    // The children: Lucy is upper elementary, Ari and Bea adolescents.
    static let lucy = UUID().uuidString
    static let ari = UUID().uuidString
    static let bea = UUID().uuidString
    static let levels: [String: CDStudent.Level] = [lucy: .upper, ari: .adolescent, bea: .adolescent]

    static func block(
        _ lane: TimetableLaneSnapshot,
        _ weekday: Weekday? = .monday,
        oneOff: Date? = nil,
        _ start: Int,
        _ length: Int,
        _ title: String,
        teacher: TimetableLaneSnapshot? = nil,
        children: [String] = [],
        from: Date? = nil,
        until: Date? = nil
    ) -> TimetableBlockSnapshot {
        TimetableBlockSnapshot(
            laneID: lane.id,
            weekday: oneOff == nil ? weekday : nil,
            onDay: oneOff,
            values: TimetableBlockValues(
                startMinute: start, lengthMinutes: length, title: title, teacherLaneID: teacher?.id,
                studentIDs: children
            ),
            validFrom: from,
            validUntil: until
        )
    }

    static func resolve(
        _ day: Date,
        blocks: [TimetableBlockSnapshot],
        changes: [TimetableChangeSnapshot] = [],
        lessons: [ScheduleLessonSnapshot] = [],
        isSchoolDay: Bool = true
    ) -> ScheduleDay {
        ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
            day: day, lanes: lanes, blocks: blocks, changes: changes, lessons: lessons, studentLevels: levels,
            isSchoolDay: isSchoolDay, calendar: calendar
        ))
    }

    /// The titles a lane shows, in order: a block's or turn's title, a
    /// lesson's title, or a half list's titles joined with "+".
    static func titles(_ lane: TimetableLaneSnapshot, in day: ScheduleDay) -> [String] {
        (day.lane(lane.id)?.items ?? []).map { item in
            switch item.kind {
            case .block(let block): block.values.title
            case .turn(let block): "turn:" + block.values.title
            case .lesson(let lesson): lesson.snapshot.title ?? "?"
            case .halfList(let half, let lessons):
                "\(half.rawValue):" + lessons.map { $0.snapshot.title ?? "?" }.joined(separator: "+")
            }
        }
    }

    // MARK: - Stores

    /// An in-memory notebook.
    static func context() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    /// The lanes and blocks in `context` as the resolver takes them, with the
    /// changes on `day`.
    static func resolveStored(_ day: Date, in context: NSManagedObjectContext) -> ScheduleDay {
        let timetable = TimetableService.timetable(from: day, through: day, in: context, calendar: calendar)
        return ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
            day: day, lanes: timetable.lanes, blocks: timetable.blocks, changes: timetable.changes,
            calendar: calendar
        ))
    }

    /// The titles `laneName`'s lane shows on `day`, from the store.
    static func storedTitles(_ laneName: String, on day: Date, in context: NSManagedObjectContext) -> [String] {
        let resolved = resolveStored(day, in: context)
        guard let lane = resolved.lanes.first(where: { $0.lane.name == laneName }) else { return [] }
        return lane.items.compactMap { $0.block?.values.title }
    }
}
