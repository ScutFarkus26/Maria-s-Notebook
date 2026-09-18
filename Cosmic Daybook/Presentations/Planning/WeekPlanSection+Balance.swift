// WeekPlanSection+Balance.swift
// Balancing every day currently on the strip, in one go.
//
// The same gesture the day columns carry, for a guide who is looking at the
// week rather than at Tuesday. It runs day by day through `DayBalanceService`
// for exactly that reason — a clash is a within-day, within-half thing, so a
// week-wide pass is five day-wide passes and never a rule of its own.
//
// One Undo covers the lot: the days are collected into a single map of the
// times each rewrite replaced, so taking it back puts the whole strip down
// where it was rather than leaving four days changed and one restored.

import SwiftUI
import CoreData

extension WeekPlanSection {
    /// Pending presentations on `day`, in the order its column draws them —
    /// matched to `WeekDayColumn.scheduledLessonsForDay`, since the balancer's
    /// idea of the day has to be the one the guide is looking at.
    private func pendingPresentations(on day: Date) -> [CDLessonAssignment] {
        lessonAssignments.filter { assignment in
            guard let scheduled = assignment.scheduledFor, !assignment.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day)
        }
        .sorted(by: LessonAssignmentOrdering.isOrderedBefore)
    }

    func balanceVisibleDays() {
        let context = viewContext
        var daysRearranged = 0
        var unresolved: Set<UUID> = []
        var restoring: [UUID: Date] = [:]

        adaptiveWithAnimation(WeekDayColumn.balanceAnimation) {
            for day in days {
                guard let result = DayBalanceService.balance(
                    day: day,
                    assignments: pendingPresentations(on: day),
                    calendar: calendar,
                    context: context
                ) else { continue }
                unresolved.formUnion(result.unresolvedStudentIDs)
                guard result.movedCount > 0 else { continue }
                daysRearranged += 1
                restoring.merge(result.previousTimes) { first, _ in first }
            }
        }

        ToastService.shared.show(
            summary(daysRearranged: daysRearranged, unresolved: unresolved, context: context),
            type: unresolved.isEmpty ? .success : .warning,
            duration: 4,
            undoAction: restoring.isEmpty ? nil : {
                // Toast buttons fire on the main actor; this only borrows that.
                MainActor.assumeIsolated {
                    adaptiveWithAnimation(WeekDayColumn.balanceAnimation) {
                        DayBalanceService.restore(restoring, in: context)
                    }
                }
            }
        )
    }

    /// Days rather than lessons, because that is the unit the guide just acted
    /// on — "rearranged 3 days" tells him where to look, "moved 7 lessons"
    /// does not.
    private func summary(
        daysRearranged: Int,
        unresolved: Set<UUID>,
        context: NSManagedObjectContext
    ) -> String {
        let moved: String
        switch daysRearranged {
        case 0: moved = "Nothing to rearrange on these days."
        case 1: moved = "Rearranged 1 day."
        default: moved = "Rearranged \(daysRearranged) days."
        }
        return [moved, DayBalanceService.stillDoubledSentence(unresolved, context: context)]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
