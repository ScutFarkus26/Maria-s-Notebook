// ScheduleLessonPlan.swift
// The guide's planned lessons as Schedules reads them: each one's day, half
// or set time, and place in its half, from the presentation itself. The
// notebook's page and MCP read lessons through here (with their names), and
// the booking publisher writes the same placement into bookings (without).
// Notebook only: the Daybook Assistant reads bookings instead.

import CoreData
import Foundation

enum ScheduleLessonPlan {

    /// One planned presentation, placed.
    struct Planned {
        let presentation: CDLessonAssignment
        let id: UUID
        /// Start of the day it's planned for.
        let day: Date
        let half: ScheduleDayHalf
        /// A set time, minutes after midnight; nil for only a half.
        let minute: Int?
        /// Its place among the day's lessons in that half, from 0.
        let order: Int
    }

    /// The presentations planned from `start` through the day before `end`
    /// (scheduled, not yet given), as `schedule_for_range` reads them
    /// (`TodayDataFetcher.fetchLessons`), placed. A half's order counts every
    /// lesson in it, timed ones too, in the order of `scheduledFor`, which is
    /// how the planner keeps the guide's order.
    static func planned(
        from start: Date,
        to end: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> [Planned] {
        let presentations = TodayDataFetcher.fetchLessons(day: start, nextDay: end, context: context)
            .filter { !$0.isPresented && $0.scheduledFor != nil }
        var placed: [Planned] = []
        for presentation in presentations {
            guard let id = presentation.id, let at = presentation.scheduledFor else { continue }
            var minute: Int?
            var half = ScheduleDayHalf.morning
            switch DayHalfPlanner.moment(of: at, using: calendar) {
            case .half(let period):
                half = period == .morning ? .morning : .afternoon
            case .time(let date):
                let time = TimetableDay.minute(of: date, calendar: calendar)
                minute = time
                half = ScheduleDayHalf(minute: time)
            }
            placed.append(Planned(
                presentation: presentation, id: id, day: calendar.startOfDay(for: at), half: half,
                minute: minute, order: 0
            ))
        }
        let halves = Dictionary(grouping: placed) { HalfKey(day: $0.day, half: $0.half) }
        return halves.values.flatMap { group in
            group.sorted(by: plannedFirst).enumerated().map { order, item in
                Planned(
                    presentation: item.presentation, id: item.id, day: item.day, half: item.half,
                    minute: item.minute, order: order
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            if lhs.half != rhs.half { return lhs.half < rhs.half }
            return lhs.order < rhs.order
        }
    }

    private struct HalfKey: Hashable {
        let day: Date
        let half: ScheduleDayHalf
    }

    /// Earlier `scheduledFor` first, then the lower id: the planner's order.
    private static func plannedFirst(_ lhs: Planned, _ rhs: Planned) -> Bool {
        let left = lhs.presentation.scheduledFor ?? .distantPast
        let right = rhs.presentation.scheduledFor ?? .distantPast
        if left != right { return left < right }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// The guide's lessons on `day` for the resolver, with their names (the
    /// notebook and MCP; never the Assistant).
    static func lessons(
        on day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> [ScheduleLessonSnapshot] {
        let start = calendar.startOfDay(for: day)
        let end = TimetableService.dayAfter(start, calendar: calendar)
        return planned(from: start, to: end, in: context, calendar: calendar).map { item in
            let presentation = item.presentation
            let title = presentation.lesson?.name ?? presentation.lessonTitleSnapshot
            return ScheduleLessonSnapshot(
                id: item.id, title: title?.trimmed(), half: item.half, minute: item.minute, order: item.order,
                studentIDs: presentation.studentIDs
            )
        }
    }

    /// Every child's level, by student ID, for the resolver's adolescent placement.
    static func studentLevels(in context: NSManagedObjectContext) -> [String: CDStudent.Level] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Student")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id", "levelRaw"]
        let rows = (try? context.fetch(request)) ?? []
        var levels: [String: CDStudent.Level] = [:]
        for row in rows {
            guard let id = row["id"] as? UUID else { continue }
            levels[id.uuidString] = CDStudent.Level(rawValue: row["levelRaw"] as? String ?? "") ?? .lower
        }
        return levels
    }
}
