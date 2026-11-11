// LessonTimeChoices.swift
// The start times the lesson time picker offers as buttons, and which half of
// the day a time falls in. Pure values: no dates, no Core Data.
//
// Every quarter hour from 8:45 to 11:00 and from 1:00 to 3:15, ten each
// (docs/Plans/Plan - Lesson times on cards.md, decision 3). The hours live
// here only; a setting for them was ruled out.

import Foundation

/// A start time on the clock, with no day attached. The picker hands one back
/// as an hour and a minute, never as a `Date`, so stray seconds can't ride along.
nonisolated struct LessonClockTime: Hashable, Sendable, Comparable {
    /// 0–23.
    let hour: Int
    /// 0–59.
    let minute: Int

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(minutesAfterMidnight minutes: Int) {
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        self.init(hour: clamped / 60, minute: clamped % 60)
    }

    var minutesAfterMidnight: Int { hour * 60 + minute }

    /// Before noon is the morning.
    var half: DayPeriod { LessonTimeChoices.half(ofMinute: minutesAfterMidnight) }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.minutesAfterMidnight < rhs.minutesAfterMidnight }
}

nonisolated enum LessonTimeChoices {
    /// 8:45, 9:00 … 11:00, as minutes after midnight.
    static let morning: [Int] = Array(stride(from: 8 * 60 + 45, through: 11 * 60, by: 15))

    /// 1:00, 1:15 … 3:15 in the afternoon, as minutes after midnight.
    static let afternoon: [Int] = Array(stride(from: 13 * 60, through: 15 * 60 + 15, by: 15))

    /// The quick times of one half of the day.
    static func quickTimes(for half: DayPeriod) -> [Int] {
        switch half {
        case .morning: morning
        case .afternoon: afternoon
        }
    }

    /// Which half a time falls in: before noon is the morning.
    static func half(ofMinute minutes: Int) -> DayPeriod {
        minutes < 12 * 60 ? .morning : .afternoon
    }

    /// The time "Another time" starts from when a lesson has none yet: the
    /// half's first lesson hour (9:00 or 1:00).
    static func suggestedStart(for half: DayPeriod) -> LessonClockTime {
        switch half {
        case .morning: LessonClockTime(hour: 9, minute: 0)
        case .afternoon: LessonClockTime(hour: 13, minute: 0)
        }
    }
}
