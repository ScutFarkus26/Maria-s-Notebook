// WorkCheckPillMenu.swift
// What a week-plan check-in pill's right-click menu can do, and its status
// submenus, which look up the pill's rows only when the menu is shown.

import CoreData
import SwiftUI

/// What a check-in pill's right-click menu can do, handed down from
/// `WeekPlanSection`, which owns the check-in lookup, the save and the toast.
struct WorkCheckPillActions {
    /// The rows under a pill, one per child.
    let rows: (CalendarCheckInGroup) -> [CDWorkModel]
    /// Those rows named for per-child submenus.
    let children: ([CDWorkModel]) -> [WorkLogStatusMenu.Child]
    /// Logs a status on some of a pill's rows for the pill's day.
    let log: (CalendarCheckInGroup, [CDWorkModel], WorkStatus) -> Void
    let openWork: (UUID) -> Void

    /// The rows under `group`, one per child: each check-in's work in the
    /// pill's order, a row two check-ins share listed once.
    static func rows(of group: CalendarCheckInGroup, in context: NSManagedObjectContext) -> [CDWorkModel] {
        var seen: Set<NSManagedObjectID> = []
        return group.checkIns.compactMap { checkIn in
            guard let work = checkIn.resolvedWork(in: context),
                  seen.insert(work.objectID).inserted else { return nil }
            return work
        }
    }

    /// `rows` named from the strip's batched lookup, "Student" when the work
    /// names no child on file.
    static func children(
        of rows: [CDWorkModel], lookup: CalendarCheckInGrouper.Lookup
    ) -> [WorkLogStatusMenu.Child] {
        rows.compactMap { work in
            guard let id = work.id else { return nil }
            let name = lookup.studentName(for: work)
            return WorkLogStatusMenu.Child(id: id, name: name.isEmpty ? "Student" : name, work: work)
        }
    }
}

/// A pill menu's status submenus.
///
/// A view of its own so the lookup waits for the menu. `.contextMenu` calls
/// its content closure on every pass of the pill's day column, and building
/// `WorkLogStatusMenu` there resolved every check-in's work twice (once for
/// the rows, again for the named children) and named each child, for every
/// pill on the day, on every redraw. A view nested in the menu is only drawn
/// when the menu is built for display, as `WorkCardStatusMenu` and
/// `SameWorkPeersMenu` already rely on; and it reads the rows once.
struct WorkCheckPillStatusMenu: View {
    let group: CalendarCheckInGroup
    let actions: WorkCheckPillActions

    var body: some View {
        let rows = actions.rows(group)
        WorkLogStatusMenu(targets: rows, children: actions.children(rows)) { rows, status in
            actions.log(group, rows, status)
        }
    }
}

extension WorkCheckPillActions {
    /// Whether a pill's checks can be logged now: on its day or after. A pill
    /// for a later day can be moved or opened, but logging it then finished
    /// the work on that future day, or read "Logged" while the pill stayed put
    /// (bug hunt 2026-10-12, #37).
    static func canLog(_ group: CalendarCheckInGroup, today: Date = Date()) -> Bool {
        AppCalendar.startOfDay(group.sortDate) <= AppCalendar.startOfDay(today)
    }
}

/// Where a pill's Reschedule › Tomorrow lands, and what the menu calls it:
/// the next school day after today, so a Friday's check goes to Monday and
/// says so ("Monday"), the way Today's bump does (bug hunt 2026-10-12, #48).
enum WorkCheckRescheduleDay {
    static func next(
        today: Date, calendar: Calendar, nextSchoolDay: (Date) -> Date
    ) -> (day: Date, title: String) {
        let start = calendar.startOfDay(for: today)
        let day = calendar.startOfDay(for: nextSchoolDay(start))
        return (day, TodayBumpDay.title(for: day, today: start, calendar: calendar))
    }
}

/// The pill menu's "next school day" item. A view of its own so the school
/// calendar is read only when the menu is shown, not on every pass of the
/// day column (see `WorkCheckPillStatusMenu`).
struct WorkCheckNextSchoolDayButton: View {
    let move: (Date) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar

    var body: some View {
        let target = WorkCheckRescheduleDay.next(today: Date(), calendar: calendar) { day in
            SchoolCalendarService.shared.nextSchoolDaySync(after: day, using: viewContext)
        }
        Button(target.title) { move(target.day) }
    }
}

/// "Open Work" for each child under a grouped pill, looked up when the menu
/// is shown. A pill for a later day offers this in place of logging.
struct WorkCheckPillOpenWorkMenu: View {
    let group: CalendarCheckInGroup
    let actions: WorkCheckPillActions

    var body: some View {
        let children = actions.children(actions.rows(group))
        Menu {
            ForEach(children) { child in
                Button(child.name) { actions.openWork(child.id) }
            }
        } label: {
            Label("Open Work", systemImage: "arrow.forward.circle")
        }
    }
}
