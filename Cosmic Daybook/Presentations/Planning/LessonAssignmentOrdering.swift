// LessonAssignmentOrdering.swift
// The one order for a day's presentations, used wherever a day's lessons are
// listed: the Lessons & Work strip, Today, Schedules and the MCP reads
// (plan "Lesson times on cards", decision 6).
//
// Day by day; inside a day, the morning before the afternoon; inside a half,
// the lessons the guide set a time for first, in clock order, then the rest in
// the order the guide dragged them (`scheduledFor` carries that order as
// second-spaced ranks, see `DayHalfPlanner`).
//
// Two things make a bare comparison on `scheduledFor` unreliable among the
// untimed lessons: Swift's sort is not stable, and every row written before
// ordering existed still sits at midnight, so a whole day of legacy rows is a
// single tie. A tie that resolves differently on each refetch reads as the
// calendar shuffling itself. `createdAt` then `id` break the tie
// deterministically, so an untouched day keeps one order for good. The first
// drag on that day rewrites it properly.

import Foundation

enum LessonAssignmentOrdering {
    /// Where one presentation sorts, worked out once.
    struct Key: Comparable {
        /// Start of the day it's planned for; `.distantPast` with no schedule.
        let day: Date
        /// 0 for the morning, 1 for the afternoon.
        let half: Int
        /// The set time in minutes after midnight; nil for an ordering slot,
        /// which sorts after every set time in its half.
        let setMinute: Int?
        /// The stored moment, which orders the slots among themselves.
        let scheduledFor: Date
        let createdAt: Date
        let id: String

        init(_ assignment: CDLessonAssignment, using calendar: Calendar = AppCalendar.shared) {
            let scheduled = assignment.scheduledFor
            day = scheduled.map { calendar.startOfDay(for: $0) } ?? .distantPast
            half = scheduled.map { DayPeriod(scheduledFor: $0, using: calendar) == .morning ? 0 : 1 } ?? 0
            setMinute = DayHalfPlanner.setMinute(of: scheduled, using: calendar)
            scheduledFor = scheduled ?? .distantPast
            createdAt = assignment.createdAt ?? .distantPast
            id = assignment.id?.uuidString ?? ""
        }

        static func < (lhs: Key, rhs: Key) -> Bool {
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            if lhs.half != rhs.half { return lhs.half < rhs.half }
            switch (lhs.setMinute, rhs.setMinute) {
            case let (left?, right?) where left != right: return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil) where lhs.scheduledFor != rhs.scheduledFor:
                return lhs.scheduledFor < rhs.scheduledFor
            default: break
            }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
    }

    static func isOrderedBefore(_ lhs: CDLessonAssignment, _ rhs: CDLessonAssignment) -> Bool {
        Key(lhs) < Key(rhs)
    }

    /// `assignments` in the shared order, each one's key worked out once.
    static func sorted(
        _ assignments: [CDLessonAssignment],
        using calendar: Calendar = AppCalendar.shared
    ) -> [CDLessonAssignment] {
        assignments
            .map { (key: Key($0, using: calendar), assignment: $0) }
            .sorted { $0.key < $1.key }
            .map(\.assignment)
    }
}
