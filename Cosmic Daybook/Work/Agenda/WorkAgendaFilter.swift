// WorkAgendaFilter.swift
// The Work half's own filters — Hide Scheduled, the kind chips, the column's
// child and the roster on screen — applied to the open work in one place, so
// the grid, the pill counts and the printed sheet narrow the list the same way.

import CoreData
import Foundation

struct WorkAgendaFilter {
    /// Hide Scheduled Work. Means anything only under the All pill: the other
    /// pills already are a state, and hiding scheduled work under the
    /// Scheduled pill would empty the list it names.
    var hideScheduled = false
    var chip: WorkFilterChip = .all
    /// The kinds left on by the chips.
    var kinds: Set<WorkKind> = Set(WorkKind.allCases)
    /// The child the column is narrowing the grid to.
    var studentID: UUID?
    /// The children on screen: the enrolled roster less hidden test
    /// students. Nil leaves every row in.
    var rosterIDs: Set<UUID>?

    /// - Parameters:
    ///   - partition: the triage the pills show.
    ///   - visibility: whose each row is, for the child filter and the roster.
    func apply(
        to works: [CDWorkModel],
        partition: LessonsAndWorkPartition,
        visibility: WorkVisibility
    ) -> [CDWorkModel] {
        var works = works

        // Exactly what the Scheduled pill holds. Hiding every row with a
        // check-in still marked scheduled also hid the ones whose day has
        // passed, which is what Needs Checking is.
        if hideScheduled && chip == .all {
            let scheduled = Set(partition.work.scheduled.map(\.objectID))
            works = works.filter { !scheduled.contains($0.objectID) }
        }

        if kinds.count < WorkKind.allCases.count {
            works = works.filter { kinds.contains($0.displayKind) }
        }

        // A row shows when it is the work of a child on screen. Work of a
        // hidden test student, or of a child who has left, read as a
        // "Student" card; a row naming nobody yet (project work no child has
        // claimed) stays.
        if let rosterIDs {
            works = works.filter { work in
                let named = WorkGrouping.studentIDs(of: work)
                return named.isEmpty || named.contains { rosterIDs.contains($0) && visibility.isVisible(work, to: $0) }
            }
        }

        // The column's child filter, by the column's own definition of whose
        // work an item is — her own copy of linked work, a shared row she
        // hasn't finished her part of — so the two read alike.
        if let studentID {
            works = works.filter {
                QuietStudentsOrder.openStudentIDs(of: $0, visibility: visibility).contains(studentID)
            }
        }
        return works
    }
}
