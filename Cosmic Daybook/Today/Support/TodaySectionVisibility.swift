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
// carrying something she could act on today. One section is deliberately
// exempt and always renders — the Agenda — because for it "nothing" is itself
// the answer she came for, and on macOS it is the wide left column that would
// otherwise be a void.
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
    case agenda
    case meetings
    case goneQuiet
    case dayCards
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

    /// The day's scheduled meetings, in a small section of their own after
    /// the lessons — gone on a day with none.
    static func showsMeetings(count: Int) -> Bool { count > 0 }

    /// Open work nobody has touched in a while, after the meetings — gone
    /// when every piece of open work has been seen recently.
    static func showsGoneQuiet(count: Int) -> Bool { count > 0 }

    /// The Restock day card: only when something is needed, on the office
    /// run or to order. An assistant marking a staple Out reaches the guide
    /// here and nowhere else (no notifications).
    static func showsRestock(officeRun: Int, toOrder: Int) -> Bool { officeRun > 0 || toOrder > 0 }

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

    /// iPhone and iPad, top to bottom: the day's plan first — the lessons,
    /// led by the Next card, then its meetings and the work gone quiet — then
    /// the Needs-a-lesson card and her todo list, then what she is watching
    /// (ready-for-next, following presentations, observations), then the
    /// external feeds, then the monthly nudge, the pad, and last the
    /// retrospective.
    ///
    /// There is no Right Now hero any more, on either platform: its Next up
    /// is the Next card at the top of the plan, and its "open work to check"
    /// count is Gone quiet's header plus the todo list's due check-ins.
    ///
    /// The Overdue section is deliberately absent from both orderings. It
    /// duplicated the Todos section's own "Overdue" subgroup with a single row
    /// that only navigated away; `DeadlinesSectionView` is kept in the
    /// codebase, just not placed on Today.
    static let phoneOrder: [TodaySection] = [
        .agenda,
        .meetings,
        .goneQuiet,
        .dayCards,
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

    /// macOS left column, the wide one: the day's plan, full height — the
    /// lessons, then the meetings, then the work gone quiet.
    static let macLeftColumnOrder: [TodaySection] = [.agenda, .meetings, .goneQuiet]

    /// macOS right column, 340 pt: the phone ordering minus the plan.
    static let macRightColumnOrder: [TodaySection] = phoneOrder.filter {
        !macLeftColumnOrder.contains($0)
    }
}
