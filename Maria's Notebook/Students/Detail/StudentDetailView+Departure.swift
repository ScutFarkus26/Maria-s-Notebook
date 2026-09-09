// StudentDetailView+Departure.swift
// The warning shown when a child being withdrawn or transferred is still
// named on lessons planned but not yet given. Those plans generate work
// naming her when they are presented, so the point of departure is where
// she comes off them — see `StudentDeparturePlans`.

import CoreData
import SwiftUI

extension StudentDetailView {
    var departureAlertIsPresented: Binding<Bool> {
        Binding(
            get: { !pendingDeparturePlans.isEmpty },
            set: { if !$0 { pendingDeparturePlans = [] } }
        )
    }

    var departureAlertMessage: String {
        let listed = pendingDeparturePlans.prefix(8)
            .map { "• " + StudentDeparturePlans.describe($0, in: viewContext) }
        let more = pendingDeparturePlans.count - listed.count
        let tail = more > 0 ? "\n• and \(more) more" : ""
        return "\(student.firstName) is still on \(pendingDeparturePlans.count) planned "
            + (pendingDeparturePlans.count == 1 ? "lesson" : "lessons")
            + ". If she stays on them, the work generated when they are given will name her.\n\n"
            + listed.joined(separator: "\n") + tail
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
