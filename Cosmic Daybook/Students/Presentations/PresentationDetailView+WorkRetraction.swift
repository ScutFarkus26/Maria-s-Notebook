// PresentationDetailView+WorkRetraction.swift
// Saving after a child has been taken off a presentation that already
// generated work for her. The work would otherwise go on naming her while the
// presentation no longer does — see `PresentationWorkRetraction`.

import SwiftUI

extension PresentationDetailContentView {
    func handleSaveAndDone() {
        // Taking a child off a presentation leaves the work it generated still
        // naming her. Show what would change and let the guide decide.
        let plans = vm.workRetractionPlans()
        if !plans.isEmpty {
            vm.offerWorkRetraction(plans)
            return
        }
        saveAndDone(retractingWork: [])
    }

    /// Saves the edits, then closes the sheet — or, when the save was for How
    /// It Went (`continueToHowItWent`), opens it on the saved record.
    func saveAndDone(retractingWork plans: [WorkRemovalPlan]) {
        let thenHowItWent = howItWentAfterSave
        howItWentAfterSave = false
        vm.save(
            studentsAll: studentsAll,
            lessons: lessons,
            lessonAssignmentsAll: lessonAssignmentsAll,
            calendar: calendar,
            retractingWork: plans
        ) {
            if thenHowItWent {
                showHowItWent()
            } else {
                handleDone()
            }
        }
    }

    /// Clears only the flag: the plans travel with the alert (G1), and each
    /// button clears them itself.
    var workRetractionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { vm.showsWorkRetraction },
            set: { vm.showsWorkRetraction = $0 }
        )
    }

    /// The plans the alert presents; nil when there are none, so it can't show empty.
    var presentedWorkRetraction: [WorkRemovalPlan]? {
        vm.pendingWorkRetraction.isEmpty ? nil : vm.pendingWorkRetraction
    }

    func workRetractionMessage(for plans: [WorkRemovalPlan]) -> String {
        let lines = PresentationWorkRetraction.describe(plans, in: viewContext)
        return "This presentation already gave follow-up work to a child you're taking off. "
            + "Take them off that work too?\n\n"
            + lines.map { "• " + $0 }.joined(separator: "\n")
    }
}

extension View {
    /// The plans are the alert's `presenting:` data, so each button reads the
    /// plans it was shown rather than state its binding may already have
    /// cleared (G1).
    // swiftlint:disable:next function_parameter_count
    func workRetractionAlert(
        isPresented: Binding<Bool>,
        plans: [WorkRemovalPlan]?,
        message: @escaping ([WorkRemovalPlan]) -> String,
        onRemove: @escaping ([WorkRemovalPlan]) -> Void,
        onKeep: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        alert("Also Remove From Work?", isPresented: isPresented, presenting: plans) { plans in
            Button("Remove From Work", role: .destructive) { onRemove(plans) }
            Button("Keep the Work", action: onKeep)
            Button("Cancel", role: .cancel, action: onCancel)
        } message: { plans in
            Text(message(plans))
        }
    }
}
