// WeekPlanSection+ShowFirst.swift
// The strip cards' "to check first" marks: each pending presentation's
// children's open work from earlier in its sequence (`WorkToShowFirst`).
//
// Split from WeekPlanSection+Data.swift for SwiftLint's file-length limit; the
// state these read is declared in WeekPlanSection.swift.

import CoreData
import SwiftUI

extension WeekPlanSection {

    /// What `WorkToShowFirst` is asked for: every pending presentation on a
    /// loaded day, keyed by its id, with its lesson and children.
    static func showFirstRequests(_ byDay: [Date: [CDLessonAssignment]]) -> [UUID: WorkToShowFirst.Request] {
        var requests: [UUID: WorkToShowFirst.Request] = [:]
        for assignment in byDay.values.joined() {
            guard let id = assignment.id else { continue }
            requests[id] = WorkToShowFirst.Request(
                lessonID: assignment.resolvedLessonID.uuidString,
                studentIDs: Set(assignment.resolvedStudentIDs)
            )
        }
        return requests
    }

    /// The cards' amber marks, for every loaded day in one fetch. Nothing is
    /// read while the strip shows only work.
    func refreshWorkToShowFirst() {
        guard visibleKinds.showsPresentations else {
            if !workToShowFirst.isEmpty { workToShowFirst = [:] }
            return
        }
        let byDay = Self.scheduledByDay(Array(lessonAssignments), days: days, calendar: calendar)
        let found = WorkToShowFirst.find(
            Self.showFirstRequests(byDay), order: lessonOrder, in: viewContext
        )
        // Most refreshes find what is already marked; writing it again would
        // redraw every card.
        if Self.markedWork(found) != Self.markedWork(workToShowFirst) {
            workToShowFirst = found
        }
    }

    private static func markedWork(
        _ marks: [UUID: WorkToShowFirst.ByChild]
    ) -> [UUID: [UUID: [WorkToShowFirst.ItemID]]] {
        marks.mapValues { $0.mapValues { $0.map(\.id) } }
    }

    /// What a marked chip's list does: open the work, or put it on today's checks.
    var showFirstActions: PresentationPlannerCard.ShowFirstActions {
        PresentationPlannerCard.ShowFirstActions(
            openWork: onOpenWork,
            checkToday: { work in
                WorkCheckInService(context: viewContext).scheduleCheck(for: work, on: AppCalendar.startOfDay(Date()))
                if saveCoordinator.save(viewContext, reason: "Check earlier work today") {
                    dependencies.toastService.show("Added to today's checks", type: .success, duration: 3)
                }
                Task { await refreshCheckIns() }
            }
        )
    }
}
