// WorkToShowFirst+Actions.swift
// What the "to check first" lists do with a row: log it from the present
// sheet, or put it on today's checks from a strip card.
//
// Both re-check the row before writing, because a list can be older than the
// work: the row may have been logged in the work sheet, on another device or
// over MCP since it was read. A shared row (project or book-club work) is one
// row for everyone on it, so it is never logged from here; logging it would
// close it for her classmates too.

import CoreData
import Foundation

extension WorkToShowFirst {

    // MARK: - Logging from the present sheet

    /// Why a row wasn't logged.
    enum LogRefusal: Error, Equatable {
        /// Logged, closed or deleted since the list was read.
        case noLongerOpen
        /// A row other children are on too: logging it would close theirs.
        case sharedWithOthers
    }

    /// Logs one row for its child through `WorkLogService.log`, as every
    /// other log does, so it comes with an Undo. Refuses a row that is no
    /// longer open for her, and one whose log would close anyone else's part.
    static func log(
        _ item: Item,
        as status: WorkStatus,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator?
    ) throws -> WorkLogService.Receipt {
        let work = item.work
        guard !work.isDeleted, work.managedObjectContext != nil, work.status.isOpen,
              QuietStudentsOrder.openStudentIDs(of: work).contains(item.studentID) else {
            throw LogRefusal.noLongerOpen
        }
        guard WorkLogService.studentsLogged(on: work, in: context) == [item.studentID] else {
            throw LogRefusal.sharedWithOthers
        }
        return try WorkLogService.log(
            [WorkLogService.Entry(work: work, status: status)],
            context: context,
            saveCoordinator: saveCoordinator
        )
    }

    // MARK: - Check Today from a strip card

    /// Where the work stands against today's checks, read from its check-ins.
    enum TodayCheck: Equatable {
        /// A check is on today already: still to do, or done (`checked`).
        case onToday(checked: Bool)
        /// Its next planned check is on a later day; Check Today moves it.
        case movesFrom(Date)
        /// Nothing later is planned; Check Today adds one (or brings an
        /// overdue one up to today).
        case adds
    }

    /// The check-in `WorkCheckInService.scheduleCheck` would move: the
    /// earliest still scheduled.
    private static func nextScheduledCheck(of work: CDWorkModel, in context: NSManagedObjectContext) -> CDWorkCheckIn? {
        WorkLogService.scheduledCheckIns(of: work, in: context).min { lhs, rhs in
            let lhsDate = lhs.date ?? .distantFuture
            let rhsDate = rhs.date ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }

    static func todayCheck(
        for work: CDWorkModel, today: Date = Date(), in context: NSManagedObjectContext
    ) -> TodayCheck {
        let day = AppCalendar.startOfDay(today)
        if let onToday = WorkCheckInService(context: context).blockingCheckIn(of: work, on: day) {
            return .onToday(checked: onToday.status == .completed)
        }
        if let date = nextScheduledCheck(of: work, in: context)?.date, AppCalendar.startOfDay(date) > day {
            return .movesFrom(date)
        }
        return .adds
    }

    /// What Check Today did.
    enum CheckTodayOutcome: Equatable {
        case added
        case moved(from: Date)
        case alreadyOnToday
        case noLongerOpen
        case childHasLeft
        case saveFailed
        /// A row other children are on too: its one check is theirs as well.
        case sharedWithOthers
    }

    /// Puts the row on today's checks without ever making a second check for
    /// the day: one already on today is left alone, a later planned one moves
    /// up, and otherwise one is added. `today` is the check day (`checkDay`).
    /// Nothing is written for closed work, a child who has left the class, or
    /// a row other children are on (moving its check would move theirs; bug
    /// hunt 2026-10-16 #5). Saved on its own, and taken back alone if the
    /// save fails.
    static func checkToday(
        _ item: Item,
        today: Date = Date(),
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) -> CheckTodayOutcome {
        let work = item.work
        guard !work.isDeleted, work.managedObjectContext != nil, work.status.isOpen else { return .noLongerOpen }
        if let child = StudentRepository(context: context).fetchStudent(id: item.studentID), !child.isEnrolled {
            return .childHasLeft
        }
        guard WorkLogService.studentsLogged(on: work, in: context) == [item.studentID] else {
            return .sharedWithOthers
        }
        let day = AppCalendar.startOfDay(today)
        let plan = todayCheck(for: work, today: day, in: context)
        if case .onToday = plan { return .alreadyOnToday }
        let saved = saveCoordinator.saveEdit(in: context, reason: "Check earlier work today") {
            _ = WorkCheckInService(context: context).scheduleCheck(for: work, on: day)
        }
        guard saved else { return .saveFailed }
        if case .movesFrom(let date) = plan { return .moved(from: date) }
        return .added
    }

    /// The toast after Check Today, and how it looks.
    /// `day` is the check day when it isn't `now`'s (a weekend's Monday).
    static func message(
        for outcome: CheckTodayOutcome, day: Date? = nil, now: Date = Date()
    ) -> (text: String, type: ToastType) {
        let words = CheckDayWords(day, now: now)
        switch outcome {
        case .added:
            return ("Added to \(words.checks)", .success)
        case .moved(let from):
            return ("Moved the check on \(dayName(from, now: now)) to \(words.inSentence)", .success)
        case .alreadyOnToday:
            return ("That work is already on \(words.checks)", .info)
        case .noLongerOpen:
            return ("That work has already been logged, so no check was added.", .info)
        case .childHasLeft:
            return ("That child has left the class, so no check was added.", .info)
        case .saveFailed:
            return ("Couldn't add that check. Try again.", .error)
        case .sharedWithOthers:
            return (
                "That work is shared with classmates, so its check wasn't moved. Open the work to change it.",
                .info
            )
        }
    }

    /// The popover's button for a row in this state. `day` is the check day
    /// when it isn't `now`'s: "Check Monday" at the weekend.
    static func checkTodayTitle(_ plan: TodayCheck, day: Date? = nil, now: Date = Date()) -> String {
        let words = CheckDayWords(day, now: now)
        switch plan {
        case .onToday(let checked):
            return checked ? words.checkedTitle : "On \(words.checksTitle)"
        case .movesFrom(let date):
            return isWithinTheWeek(date, now: now)
                ? "Move \(dayName(date, now: now))'s Check to \(words.name)"
                : "Move the \(date.formatted(.dateTime.month(.abbreviated).day())) Check to \(words.name)"
        case .adds:
            return words.checkTitle
        }
    }

    /// How the check day reads: "Today", "Monday" within the coming week, or
    /// "Thu, Jan 7" further out (after a long break). A weekday takes a
    /// possessive ("Monday's checks"); a date doesn't ("the checks for
    /// Thu, Jan 7"), and nor does Checked, which would read as done already.
    private struct CheckDayWords {
        let name: String
        private let isToday: Bool
        private let isDate: Bool

        init(_ day: Date?, now: Date) {
            guard let day, !AppCalendar.shared.isDate(day, inSameDayAs: now) else {
                name = "Today"
                isToday = true
                isDate = false
                return
            }
            name = WorkToShowFirst.dayName(day, now: now)
            isToday = false
            isDate = !WorkToShowFirst.isWithinTheWeek(day, now: now)
        }

        /// "today", "Monday", "Thu, Jan 7": the day inside a sentence.
        var inSentence: String { isToday ? "today" : name }
        /// "today's checks", "Monday's checks", "the checks for Thu, Jan 7".
        var checks: String { isDate ? "the checks for \(name)" : "\(inSentence)'s checks" }
        /// "Today's Checks", "Monday's Checks", "the Checks for Thu, Jan 7".
        var checksTitle: String { isDate ? "the Checks for \(name)" : "\(name)'s Checks" }
        /// "Check Today", "Check Monday", "Check on Thu, Jan 7".
        var checkTitle: String { isDate ? "Check on \(name)" : "Check \(name)" }
        /// "Checked Today", "Checked for Monday".
        var checkedTitle: String { isToday ? "Checked Today" : "Checked for \(name)" }
    }

    // MARK: - Days

    /// The day Check Today puts a check on: today, or the next school day
    /// when today isn't one. The strip has no column for a weekend or
    /// holiday, so a check put there would show nowhere (bug hunt 2026-10-16 #4).
    static func checkDay(from now: Date = Date(), in context: NSManagedObjectContext) -> Date {
        AppCalendar.startOfDay(SchoolCalendarService.shared.schoolDaySync(onOrAfter: now, using: context))
    }

    /// "Today", "Thursday" within the coming week, else "Thu, Oct 23": a
    /// weekday alone more than six days out would name the wrong week.
    static func dayName(_ day: Date, now: Date = Date()) -> String {
        let calendar = AppCalendar.shared
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if isWithinTheWeek(day, now: now) { return day.formatted(.dateTime.weekday(.wide)) }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// One to six days after `now`'s day.
    private static func isWithinTheWeek(_ day: Date, now: Date) -> Bool {
        let days = AppCalendar.shared.dateComponents(
            [.day], from: AppCalendar.startOfDay(now), to: AppCalendar.startOfDay(day)
        ).day ?? 0
        return (1...6).contains(days)
    }
}
