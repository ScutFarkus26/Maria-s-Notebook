// ClassAreaChecklistView+ReadyLens.swift
// The Ready to Present lens's one action: a row's Plan (the Class column on the Mac and
// iPad, by the name on the iPhone) opens the present-a-lesson sheet with a draft for
// exactly the row's ready children, the same sheet and draft the card's Present uses.
// A draft the sheet neither records nor schedules goes away again (finishPresentation).

import SwiftUI

extension ClassAreaChecklistView {

    func planReady(lessonID: UUID?) {
        guard let lessonID,
              let draft = viewModel.makeReadyDraft(
                lessonID: lessonID, studentOrder: columnStudentIDs, context: viewContext
              )
        else { return }
        viewModel.clearSelection()
        afterClosingCard {
            presentationTarget = ChecklistPresentationTarget(assignment: draft, fromSelection: false)
        }
    }
}
