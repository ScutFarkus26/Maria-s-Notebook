// AttendanceExpandedView+Undoable.swift
// The roll's two sweeping changes, Close Arrival and Reset Day, each with an
// Undo in the toast that follows.

import SwiftUI

extension AttendanceExpandedView {

    // MARK: - Closing arrival

    var arrivalControl: some View {
        AttendanceArrivalControl(
            viewModel: viewModel,
            isEditing: isEditing,
            onClose: closeArrival,
            onReopen: {
                withAnimation(.smooth(duration: 0.3)) { viewModel.reopenArrival() }
            }
        )
    }

    func closeArrival() {
        guard let undo = withAnimation(.smooth(duration: 0.3), {
            viewModel.closeArrival(modelContext: viewContext)
        }) else { return }
        saved("Close arrival")
        let count = undo.records.count
        let context = viewContext
        let model = viewModel
        let coordinator = saveCoordinator
        let onChange = onChange
        dependencies.toastService.show(
            count == 1 ? "Marked 1 absent" : "Marked \(count) absent",
            undoAction: {
                // Toast buttons fire on the main actor; this only borrows that.
                MainActor.assumeIsolated {
                    withAnimation(.smooth(duration: 0.3)) {
                        _ = model.undoCloseArrival(undo, modelContext: context)
                    }
                    coordinator.save(context, reason: "Undo close arrival")
                    onChange()
                }
            }
        )
    }

    // MARK: - Reset

    func resetDay() {
        guard let undo = viewModel.resetDay(modelContext: viewContext) else { return }
        saved("Reset day")
        let context = viewContext
        let model = viewModel
        let coordinator = saveCoordinator
        let onChange = onChange
        dependencies.toastService.show(
            "Day reset",
            undoAction: {
                MainActor.assumeIsolated {
                    guard model.undoReset(undo, modelContext: context) > 0 else { return }
                    coordinator.save(context, reason: "Undo reset day")
                    onChange()
                }
            }
        )
    }

    /// "Reset Tuesday, September 29?"
    var resetTitle: String {
        viewModel.isToday ? "Reset today?" : "Reset \(DateFormatters.fullDate.string(from: date))?"
    }
}
