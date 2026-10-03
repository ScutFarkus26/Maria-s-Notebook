// CalendarDayActivationGate.swift
// The decision behind `onCalendarDayChange`'s scene-activation path.

import Foundation

/// Decides whether a scene activation owes `onCalendarDayChange`'s action a run.
///
/// The actions refresh day-keyed content: the school days since a child's last
/// lesson, which date is "today". Activation used to run them every time, so each
/// unlock, app switch or Control Center pull re-ran a fetch of every presented
/// assignment with nothing changed.
/// What they read besides the store (which their own observers watch) is the day,
/// the school calendar (which days count) and the counter epoch (where day counts
/// start); an activation is due only when one of those moved since the view last
/// caught up. Kept free of SwiftUI so it can be tested.
struct CalendarDayActivationGate {

    /// What day-keyed content was last brought up to date against.
    struct Stamp: Equatable {
        let day: Date
        let schoolDayVersion: Int
        let counterEpoch: Date?

        static func current(now: Date = Date()) -> Stamp {
            Stamp(
                day: AppCalendar.startOfDay(now),
                schoolDayVersion: SchoolDayDataVersion.current,
                counterEpoch: SchoolYearCounters.epoch
            )
        }
    }

    private(set) var lastStamp: Stamp?

    /// The content was just brought up to date: the view appeared (callers load
    /// on appear) or the action ran for a day-change notification.
    mutating func record(_ stamp: Stamp) {
        lastStamp = stamp
    }

    /// The scene became active: true when the day, the school calendar or the
    /// counter epoch moved since the last record, or nothing was recorded yet.
    /// Records `stamp` either way.
    mutating func activationIsDue(_ stamp: Stamp) -> Bool {
        defer { lastStamp = stamp }
        return stamp != lastStamp
    }
}
