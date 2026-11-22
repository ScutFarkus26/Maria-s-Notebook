// TodayView+QuickNote.swift
// "Given — Quick Note" on Today's lesson rows and Next card: the lesson is
// recorded as given for the children who were there (`LessonQuickNote.markGiven`,
// the "Mark Presented Now" path), then the quick note opens on it — the Quick
// Note window on the Mac, a sheet on the iPad and iPhone.

import SwiftUI

extension TodayView {

    func markGivenWithQuickNote(_ sl: CDLessonAssignment) {
        do {
            let result = try LessonQuickNote.markGiven(
                sl, context: viewContext, saveCoordinator: saveCoordinator
            )
            viewModel.reload()
            toast(TodayMarkPresented.message(keptOnPlan: result.keptOnPlan.map { displayNameForID($0) }))
        } catch {
            toast(PresentationFailureMessage.message(
                for: error, fallback: "Couldn't record the presentation. Nothing was changed. Try again."
            ))
            return
        }
        if let id = sl.id { openLessonQuickNote(for: id) }
    }

    /// The quick note on the presentation with `id`.
    func openLessonQuickNote(for id: UUID) {
        #if os(macOS)
        LessonQuickNoteTarget.shared.open(id)
        openWindow(id: LessonQuickNote.windowID)
        #else
        activeSheet = .lessonQuickNote(presentationID: id)
        #endif
    }
}
