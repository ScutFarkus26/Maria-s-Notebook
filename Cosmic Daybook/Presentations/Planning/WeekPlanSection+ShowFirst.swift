// WeekPlanSection+ShowFirst.swift
// The strip cards' "to check first" marks: each pending presentation's
// children's open work from earlier in its sequence (`WorkToShowFirst`).
//
// Split from WeekPlanSection+Data.swift for SwiftLint's file-length limit; the
// state these read is declared in WeekPlanSection.swift.

import CoreData
import SwiftUI

extension WeekPlanSection {

    /// School days read either side of the ones on screen, so a card scrolled
    /// in is already marked. The strip loads about 45 days; the marks need
    /// only these.
    static let showFirstBufferDays = 2

    /// The days whose cards are marked: those on screen and a few either side.
    static func showFirstDays(_ days: [Date], leadingDay: Date?) -> [Date] {
        guard !days.isEmpty else { return [] }
        let leading = leadingDay.flatMap { days.firstIndex(of: $0) } ?? 0
        let start = max(0, leading - showFirstBufferDays)
        let end = min(days.count, leading + visibleDayCount + showFirstBufferDays)
        guard start < end else { return [] }
        return Array(days[start..<end])
    }

    /// What `WorkToShowFirst` is asked for: every pending presentation on one
    /// of `days`, keyed by its id, with its lesson and children.
    static func showFirstRequests(
        _ byDay: [Date: [CDLessonAssignment]], days: [Date], calendar: Calendar
    ) -> [UUID: WorkToShowFirst.Request] {
        var requests: [UUID: WorkToShowFirst.Request] = [:]
        for day in days {
            for assignment in byDay[calendar.startOfDay(for: day)] ?? [] {
                guard let id = assignment.id else { continue }
                requests[id] = WorkToShowFirst.Request(
                    lessonID: assignment.resolvedLessonID.uuidString,
                    studentIDs: Set(assignment.resolvedStudentIDs)
                )
            }
        }
        return requests
    }

    /// Everything the marks depend on, as the strip's `.task(id:)`: the
    /// cards near the screen, whether presentations are shown at all, and a
    /// count bumped by every save touching work and by the card data's
    /// reload. One change, one read, whichever of them moved.
    struct ShowFirstKey: Hashable {
        let requests: [UUID: WorkToShowFirst.Request]
        let showsPresentations: Bool
        let version: Int
    }

    func showFirstKey(_ byDay: [Date: [CDLessonAssignment]]) -> ShowFirstKey {
        let shows = visibleKinds.showsPresentations
        return ShowFirstKey(
            requests: shows
                ? Self.showFirstRequests(
                    byDay, days: Self.showFirstDays(days, leadingDay: leadingDay), calendar: calendar
                )
                : [:],
            showsPresentations: shows,
            version: showFirstVersion
        )
    }

    /// The cards' amber marks, for the days near the screen in one fetch.
    /// Nothing is read while the strip shows only work.
    func refreshWorkToShowFirst(_ key: ShowFirstKey) {
        guard key.showsPresentations, !key.requests.isEmpty else {
            if !workToShowFirst.isEmpty { workToShowFirst = [:] }
            return
        }
        let found = WorkToShowFirst.find(key.requests, sequences: showFirstSequences, in: viewContext)
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
            checkToday: { item in
                let outcome = WorkToShowFirst.checkToday(
                    item, context: viewContext, saveCoordinator: saveCoordinator
                )
                let message = WorkToShowFirst.message(for: outcome)
                dependencies.toastService.show(message.text, type: message.type, duration: 3)
                showFirstVersion &+= 1
                Task { await refreshCheckIns() }
            }
        )
    }
}
