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
            vm.pendingWorkRetraction = plans
            return
        }
        saveAndDone(retractingWork: [])
    }

    func saveAndDone(retractingWork plans: [WorkRemovalPlan]) {
        vm.save(
            studentsAll: studentsAll,
            lessons: lessons,
            lessonAssignmentsAll: lessonAssignmentsAll,
            calendar: calendar,
            retractingWork: plans
        ) {
            handleDone()
        }
    }

    var workRetractionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { !vm.pendingWorkRetraction.isEmpty },
            set: { if !$0 { vm.pendingWorkRetraction = [] } }
        )
    }

    var workRetractionMessage: String {
        let lines = PresentationWorkRetraction.describe(vm.pendingWorkRetraction, in: viewContext)
        return "This presentation already generated work for a child you are removing. "
            + "Take her off that work too, so the two records agree?\n\n"
            + lines.map { "• " + $0 }.joined(separator: "\n")
    }
}

extension View {
    func workRetractionAlert(
        isPresented: Binding<Bool>,
        message: String,
        onRemove: @escaping () -> Void,
        onKeep: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        alert("Also Remove From Work?", isPresented: isPresented) {
            Button("Remove From Work", action: onRemove)
            Button("Keep the Work", action: onKeep)
            Button("Cancel", role: .cancel, action: onCancel)
        } message: {
            Text(message)
        }
    }
}
