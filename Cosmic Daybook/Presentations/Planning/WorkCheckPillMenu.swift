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
