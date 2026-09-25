// TodaySectionVisibility.swift
// The single rule that decides which Today sections the guide sees.
//
// Today used to render every section it owns whether or not the section had
// anything in it: the reminders section arrived each morning holding forty-one
// undated Apple Reminders from last year, the day pad announced itself while
// the pad was empty, the parent-report nudge stayed up for three weeks after
// the cycle closed. A screen that always looks the same tells the guide
// nothing, so she stopped reading it.
//
// The rule here is the opposite: a section earns its place on the screen by
// carrying something she could act on today. Two sections are deliberately
// exempt and always render — Right Now and the Agenda — because for those
// "nothing" is itself the answer she came for, and on macOS the Agenda is a
// whole column that would otherwise be a void.
//
// Nothing here touches Core Data or reads the clock. Every function takes
// value inputs and, where a date matters, an explicit reference date, exactly
// as `LessonsAndWorkTriage` does — so every boundary below is testable.
// The section views convert their fetched rows to counts and ask here.

import Foundation

// MARK: - Sections

/// A section Today can render, in its own right. The raw values are stable
/// because they name the sections in test failures and log lines; nothing
/// persists them.
enum TodaySection: String, CaseIterable, Sendable {
    case rightNow
    case dayCards
    case agenda
    case todos
    case watching
    case readyForNext
    case followingPresentations
    case recentNotes
    case calendarEvents
    case reminders
    case parentReports
    case dayPad
    case doneToday
}

// MARK: - Visibility

/// Whether each Today section has anything worth showing.
enum TodaySectionVisibility {

    // MARK: Count-gated sections

    /// The todo list shows only when the day has todos on it. Capture survives
    /// the section disappearing: "New Todo" lives in the toolbar `+` menu.
    static func showsTodos(count: Int) -> Bool { count > 0 }

    /// External calendar feed — nothing synced for the day means nothing to say.
    static func showsCalendarEvents(count: Int) -> Bool { count > 0 }

    /// Recent observations, the guide's own writing from the last day or two.
    static func showsRecentNotes(count: Int) -> Bool { count > 0 }

    /// The retrospective roll-up (lessons presented, work checked, meetings held).
    static func showsDoneToday(total: Int) -> Bool { total > 0 }

    // MARK: Reminders

    /// Reminders show when *any* bucket has something, including the undated
    /// ones — they are still hers, they just do not belong on the fold.
    static func showsReminders(overdue: Int, dueToday: Int, anytime: Int) -> Bool {
        overdue > 0 || dueToday > 0 || anytime > 0
    }

    /// The undated pile sits behind a disclosure that is offered only when
    /// there is a pile. Whether it is *open* is the guide's stored choice
    /// (`UserDefaultsKeys.todayAnytimeRemindersExpanded`), not this rule's
    /// business — an anytime-only day still opens collapsed.
    static func showsAnytimeDisclosure(anytime: Int) -> Bool { anytime > 0 }

    // MARK: Day pad

    /// The pad shows when it has something written on it, or when the guide
    /// has deliberately opened it (from the header or the toolbar `+` menu).
    /// An empty, closed pad is noise on every single day.
    static func showsDayPad(hasBody: Bool, isExpanded: Bool) -> Bool {
        hasBody || isExpanded
    }

    // MARK: Parent reports

    /// The monthly nudge is live only inside the cycle window — day 1 through
    /// the end of day 7 of the month after the month being reported on
    /// (`ReportMonth.cycleWindow`).
    ///
    /// It was previously gated on "the cycle has opened", with no upper bound,
    /// so a month where the guide sent nothing nagged her until the next
    /// cycle replaced it. Past day 7 the reports are late, and a banner she
    /// has read and declined twenty times is not what makes her send them.
    ///
    /// Zero enrolled students, or every enrolled student already sent, hides
    /// it too.
    static func showsParentReports(now: Date, window: DateInterval, enrolled: Int, sent: Int) -> Bool {
        guard enrolled > 0, sent < enrolled else { return false }
        return window.contains(now)
    }

    // MARK: - Orderings

    /// iPhone and iPad, top to bottom: what is in front of her now (Right Now,
    /// the day's banners, the day's plan, her todo list), then what she is
    /// watching (ready-for-next, following presentations, observations), then
    /// the external feeds, then the monthly nudge, the pad, and last the
    /// retrospective.
    ///
    /// The Overdue section is deliberately absent from both orderings. It
    /// duplicated the Todos section's own "Overdue" subgroup with a single row
    /// that only navigated away; `DeadlinesSectionView` is kept in the
    /// codebase, just not placed on Today.
    static let phoneOrder: [TodaySection] = [
        .rightNow,
        .dayCards,
        .agenda,
        .todos,
        .watching,
        .readyForNext,
        .followingPresentations,
        .recentNotes,
        .calendarEvents,
        .reminders,
        .parentReports,
        .dayPad,
        .doneToday
    ]

    /// macOS left column: the phone ordering minus the agenda, which gets the
    /// right column to itself.
    static let macLeftColumnOrder: [TodaySection] = phoneOrder.filter { $0 != .agenda }

    /// macOS right column: the live agenda, full height.
    static let macRightColumnOrder: [TodaySection] = [.agenda]
}
