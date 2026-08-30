// WorkRestPreset.swift
// How long "not now" lasts.
//
// `restingUntil` is the one honest answer to work the guide isn't ready to act
// on and isn't ready to drop: `LessonsAndWorkTriage` reads it before every
// reason to nag, because resting *is* a plan. The field has been in the model
// and in the rule from the start, but the only thing that ever wrote it was a
// student meeting — so from the work grid the choices were nag or delete.
//
// These are the presets the card's menu offers. Pure and calendar-explicit so
// the boundary the rule cares about — resting ends *after* today, never on it
// — can be tested without a live clock.

import Foundation

enum WorkRestPreset: String, CaseIterable, Identifiable, Sendable {
    case nextWeek
    case twoWeeks
    case nextMonth

    var id: Self { self }

    var title: String {
        switch self {
        case .nextWeek: "Next Week"
        case .twoWeeks: "In Two Weeks"
        case .nextMonth: "Next Month"
        }
    }

    private var days: (component: Calendar.Component, value: Int) {
        switch self {
        case .nextWeek: (.day, 7)
        case .twoWeeks: (.day, 14)
        case .nextMonth: (.month, 1)
        }
    }

    /// The date the work comes back, normalised to the start of that day.
    ///
    /// Always at least tomorrow: the rule treats `restingUntil <= today` as
    /// expired, so a preset that resolved to today would set the work aside and
    /// wake it in the same breath.
    func wakeDate(from now: Date = Date(), calendar: Calendar = AppCalendar.shared) -> Date {
        let today = AppCalendar.startOfDay(now)
        let requested = calendar.date(byAdding: days.component, value: days.value, to: today) ?? today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return AppCalendar.startOfDay(max(requested, tomorrow))
    }
}
