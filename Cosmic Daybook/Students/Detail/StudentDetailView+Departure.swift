// StudentDetailView+Departure.swift
// The warning shown when a child being withdrawn or transferred is still
// named on lessons planned but not yet given. Those plans generate work
// naming her when they are presented, so the point of departure is where
// she comes off them — see `StudentDeparturePlans`.

import CoreData
import SwiftUI

extension StudentDetailView {
    /// Collects what a child being withdrawn or transferred is still committed
    /// to, stashing it for the alert. Returns true when there is something to
    /// ask about, so the caller holds the save until the guide has answered.
    func stageDepartureIfNeeded(for studentID: UUID) -> Bool {
        guard student.isEnrolled, draftEnrollmentStatus != .enrolled else { return false }
        let plans = StudentDeparturePlans.futurePlans(for: studentID, in: viewContext)
        let entries = StudentDeparturePlans.plannedEntries(for: studentID, in: viewContext)
        guard !plans.isEmpty || !entries.isEmpty else { return false }
        pendingDeparturePlans = plans
        pendingDepartureEntries = entries
        return true
    }

    var departureAlertIsPresented: Binding<Bool> {
        Binding(
            get: { !pendingDeparturePlans.isEmpty || !pendingDepartureEntries.isEmpty },
            set: {
                if !$0 {
                    pendingDeparturePlans = []
                    pendingDepartureEntries = []
                }
            }
        )
    }

    var departureAlertMessage: String {
        [plannedLessonsParagraph, yearPlanParagraph]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    /// The lessons themselves, named — these are the ones that generate work.
    /// Each part is separately typed: one long `+` chain of interpolations and
    /// ternaries costs more than the project's 100 ms type-check budget.
    private var plannedLessonsParagraph: String? {
        let count: Int = pendingDeparturePlans.count
        guard count > 0 else { return nil }
        let listed: [String] = pendingDeparturePlans.prefix(8)
            .map { "• " + StudentDeparturePlans.describe($0, in: viewContext) }
        let more: Int = count - listed.count
        let tail: String = more > 0 ? "\n• and \(more) more" : ""
        let noun: String = count == 1 ? "lesson" : "lessons"
        let opening: String = "\(student.firstName) is still on \(count) planned \(noun)."
        let consequence: String = " If she stays on them, the work generated when they are given will name her."
        let body: String = listed.joined(separator: "\n")
        return opening + consequence + "\n\n" + body + tail
    }

    /// Year-plan entries are counted, not listed: there are routinely dozens,
    /// and unlike the plans above none of them generates anything on its own.
    private var yearPlanParagraph: String? {
        let count: Int = pendingDepartureEntries.count
        guard count > 0 else { return nil }
        let noun: String = count == 1 ? "lesson" : "lessons"
        let them: String = count == 1 ? "it" : "them"
        let opening: String = "Her year plan still pencils in \(count) \(noun), "
        let effect: String = "which will go on falling behind pace. "
        let promise: String = "Removing marks \(them) skipped rather than deleting, "
        let reason: String = "so the plan is still there if she comes back."
        return opening + effect + promise + reason
    }
}

extension View {
    func departurePlansAlert(
        isPresented: Binding<Bool>,
        message: String,
        onRemove: @escaping () -> Void,
        onKeep: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        alert("Still Planned for Lessons", isPresented: isPresented) {
            Button("Remove From Plans", action: onRemove)
            Button("Keep Plans", action: onKeep)
            Button("Cancel", role: .cancel, action: onCancel)
        } message: {
            Text(message)
        }
    }
}
