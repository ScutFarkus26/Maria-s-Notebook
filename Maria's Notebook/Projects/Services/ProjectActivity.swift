// ProjectActivity.swift
// Whether a project is still running, judged from what has happened to it.
//
// `CDProject.isActive` is set true when a project is created and then never
// revisited, so on its own it says "nobody has pressed Mark Complete" rather
// than "this is live". Three projects created last year, with no sessions and
// no edits since, were all still calling themselves active. A project is live
// when something has happened to it *this school year*; last year's is dormant
// until someone touches it again.
//
// Pure — no fetch, no context — so both the Projects screen and the MCP tool
// can ask the same question and give the same answer.

import CoreData
import Foundation

enum ProjectActivity {
    /// Where a project stands.
    nonisolated enum Status: Equatable, Sendable {
        /// Something happened to it this school year.
        case active
        /// Still open, but untouched since `since` (nil when nothing is dated).
        case dormant(since: Date?)
        /// The guide marked it complete.
        case closed
    }

    /// The most recent thing that happened to this project: its last session,
    /// its last edit, or — for one that has had neither — its creation.
    ///
    /// Nonisolated so `CDProject.overlaps(_:)`, which the school-year lens calls
    /// from nonisolated code, can share this one definition. The two rules below
    /// stay on the main actor because the school-year boundary they read is a
    /// main-actor setting.
    nonisolated static func lastActivity(of project: CDProject) -> Date? {
        let sessions = (project.sessions?.allObjects as? [CDProjectSession]) ?? []
        let candidates = [
            sessions.compactMap(\.meetingDate).max(),
            project.modifiedAt,
            project.createdAt
        ].compactMap { $0 }
        return candidates.max()
    }

    /// The start of the school year `date` falls in, read through the same
    /// configurable start month/day the year lens and the grade boundary use —
    /// so changing the year start in Settings moves this line too, and the
    /// screen and the tool stay in step without either needing dependencies.
    static func currentYearStart(asOf date: Date = Date()) -> Date {
        SchoolYear.containing(
            date,
            startMonth: FloridaGradeCalculator.schoolStartMonth,
            startDay: FloridaGradeCalculator.schoolStartDay,
            calendar: AppCalendar.shared
        ).start
    }

    /// `closed` when the guide marked it complete; otherwise `active` if it has
    /// been touched since this school year began, and `dormant` if not.
    ///
    /// A project with no dates at all is treated as active: it was just made,
    /// or it is missing the stamps that would say otherwise, and hiding a
    /// project the guide cannot see a reason for is the worse failure.
    static func status(of project: CDProject, asOf date: Date = Date()) -> Status {
        guard project.isActive else { return .closed }
        guard let last = lastActivity(of: project) else { return .active }
        return last >= currentYearStart(asOf: date) ? .active : .dormant(since: last)
    }
}

nonisolated extension CDProject {
    /// True if this project's activity window (creation through its last session
    /// or edit) overlaps `range`. Projects with no creation date fail open.
    func overlaps(_ range: DateRange) -> Bool {
        guard let created = createdAt else { return true }
        if created >= range.end { return false }
        // One definition of "the last thing that happened", shared with the
        // dormancy rule, so the year lens and the Active/Dormant label can
        // never disagree about when a project was last touched.
        return (ProjectActivity.lastActivity(of: self) ?? created) >= range.start
    }
}
