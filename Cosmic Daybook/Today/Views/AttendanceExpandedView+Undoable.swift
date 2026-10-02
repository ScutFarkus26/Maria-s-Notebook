// AttendanceExpandedView+Undoable.swift
// The roll's sweeping changes, Mark N Present, Close Arrival and Reset Day,
// each with an Undo in the toast that follows.

import SwiftUI

extension AttendanceExpandedView {

    // MARK: - Marking the rest present

    /// "Mark 3 Present": everyone not marked yet. Nil when there's no one.
    var markRestPresentTitle: String? {
        let count = viewModel.unmarkedCount
        guard count > 0, !viewModel.isFuture else { return nil }
        return "Mark \(count) Present"
    }

    func markRestPresent() {
        guard let undo = withAnimation(.smooth(duration: 0.3), {
            viewModel.markUnmarkedPresent(modelContext: viewContext)
        }) else { return }
        saved("Mark the rest present")
        let count = undo.records.count
        let context = viewContext
        let model = viewModel
        let coordinator = saveCoordinator
        let onChange = onChange
        dependencies.toastService.show(
            count == 1 ? "Marked 1 present" : "Marked \(count) present",
            undoAction: {
                MainActor.assumeIsolated {
                    withAnimation(.smooth(duration: 0.3)) {
                        _ = model.undoBulkMark(undo, modelContext: context)
                    }
                    coordinator.save(context, reason: "Undo mark the rest present")
                    onChange()
                }
            }
        )
    }

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

// MARK: - One child's mark, with ⌘Z

extension AttendanceExpandedView {

    /// Makes one child's change, saves it, and puts it on Edit › Undo as
    /// "Undo `name`" (⌘Z); the undo's own opposite becomes Redo.
    func undoably(_ name: String, _ row: AttendanceRow, _ change: (AttendanceRow) -> Void) {
        let undo = viewModel.recordingUndo(for: row, modelContext: viewContext, change)
        saved(name)
        guard let undo else { return }
        register(undo, named: name)
    }

    private func register(_ undo: AttendanceViewModel.MarkUndo, named name: String) {
        guard let undoManager else { return }
        let context = viewContext
        let coordinator = saveCoordinator
        let onChange = onChange
        undoManager.registerUndo(withTarget: viewModel) { model in
            // Undo runs on the main thread, from the menu or the keyboard.
            MainActor.assumeIsolated {
                guard let redo = withAnimation(.smooth(duration: 0.2), {
                    model.undoMark(undo, modelContext: context)
                }) else { return }
                coordinator.save(context, reason: "Undo \(name.lowercased())")
                onChange()
                registerAgain(redo, named: name, on: undoManager)
            }
        }
        undoManager.setActionName(name)
    }

    /// The redo (and the redo's undo, and so on): the same step, reversed.
    private func registerAgain(_ undo: AttendanceViewModel.MarkUndo, named name: String, on manager: UndoManager) {
        let context = viewContext
        let coordinator = saveCoordinator
        let onChange = onChange
        manager.registerUndo(withTarget: viewModel) { model in
            MainActor.assumeIsolated {
                guard let next = model.undoMark(undo, modelContext: context) else { return }
                coordinator.save(context, reason: name)
                onChange()
                registerAgain(next, named: name, on: manager)
            }
        }
        manager.setActionName(name)
    }
}
