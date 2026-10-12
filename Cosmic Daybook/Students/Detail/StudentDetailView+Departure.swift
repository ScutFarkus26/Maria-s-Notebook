// StudentDetailView+Departure.swift
// The warning shown when a child being withdrawn or transferred is still
// named on lessons planned but not yet given. Those plans generate work
// naming the child when they are presented, so the point of departure is
// where the child comes off them — see `StudentDeparturePlans`.

import CoreData
import SwiftUI

/// What a departing child is still committed to, carried into the alert as
/// its `presenting:` data. The alert's binding used to clear the arrays the
/// Remove button then read, and SwiftUI doesn't document which runs first,
/// so Remove From Plans could remove nothing (bug hunt 2026-10-12 #58).
struct PendingDeparture {
    let plans: [CDLessonAssignment]
    let entries: [CDYearPlanEntry]
}

extension StudentDetailView {
    /// Collects what a child being withdrawn or transferred is still committed
    /// to, stashing it for the alert. Returns true when there is something to
    /// ask about, so the caller holds the save until the guide has answered.
    func stageDepartureIfNeeded(for studentID: UUID) -> Bool {
        guard student.isEnrolled, draftEnrollmentStatus != .enrolled else { return false }
        let plans = StudentDeparturePlans.futurePlans(for: studentID, in: viewContext)
        let entries = StudentDeparturePlans.plannedEntries(for: studentID, in: viewContext)
        guard !plans.isEmpty || !entries.isEmpty else { return false }
        pendingDeparture = PendingDeparture(plans: plans, entries: entries)
        showsDepartureAlert = true
        return true
    }

    func departureAlertMessage(for departure: PendingDeparture) -> String {
        [plannedLessonsParagraph(departure.plans), yearPlanParagraph(departure.entries)]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    /// The lessons themselves, named — these are the ones that generate work.
    /// Each part is separately typed: one long `+` chain of interpolations and
    /// ternaries costs more than the project's 100 ms type-check budget.
    private func plannedLessonsParagraph(_ plans: [CDLessonAssignment]) -> String? {
        let count: Int = plans.count
        guard count > 0 else { return nil }
        let listed: [String] = plans.prefix(8)
            .map { "• " + StudentDeparturePlans.describe($0, in: viewContext) }
        let more: Int = count - listed.count
        let tail: String = more > 0 ? "\n• and \(more) more" : ""
        let noun: String = count == 1 ? "lesson" : "lessons"
        let opening: String = "\(student.firstName) is still on \(count) planned \(noun)."
        let first: String = student.firstName
        let consequence: String = " If you leave \(first) on them, \(first) will get follow-up work when they're given."
        let body: String = listed.joined(separator: "\n")
        return opening + consequence + "\n\n" + body + tail
    }

    /// Year-plan entries are counted, not listed: there are routinely dozens,
    /// and unlike the plans above none of them generates anything on its own.
    private func yearPlanParagraph(_ entries: [CDYearPlanEntry]) -> String? {
        let count: Int = entries.count
        guard count > 0 else { return nil }
        let noun: String = count == 1 ? "lesson" : "lessons"
        let them: String = count == 1 ? "it" : "them"
        let first: String = student.firstName
        let opening: String = "\(first)'s year plan still has \(count) \(noun) planned. "
        let promise: String = "Removing marks \(them) skipped instead of deleting \(them), "
        let reason: String = "so the plan is still there if \(first) comes back."
        return opening + promise + reason
    }
}

extension View {
    /// Each button reads the departure it was shown, never state the
    /// binding may already have cleared (G1).
    // swiftlint:disable:next function_parameter_count
    func departurePlansAlert(
        isPresented: Binding<Bool>,
        departure: PendingDeparture?,
        message: @escaping (PendingDeparture) -> String,
        onRemove: @escaping (PendingDeparture) -> Void,
        onKeep: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        alert("Still Planned for Lessons", isPresented: isPresented, presenting: departure) { departure in
            Button("Remove From Plans") { onRemove(departure) }
            Button("Keep Plans", action: onKeep)
            Button("Cancel", role: .cancel, action: onCancel)
        } message: { departure in
            Text(message(departure))
        }
    }
}
