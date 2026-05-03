// TodayViewToolbarPlusMenu.swift
// Toolbar `+` menu for the Today view — mirrors the floating QuickNoteGlassButton's
// pie menu with the same five quick-capture actions, but in thumb-reach for the
// top of the screen.

import SwiftUI

extension TodayView {

    @ViewBuilder
    var toolbarPlusMenu: some View {
        Menu {
            ForEach(PieMenuAction.allCases, id: \.self) { action in
                Button {
                    perform(action)
                } label: {
                    Label(action.label, systemImage: action.icon)
                }
            }
        } label: {
            Image(systemName: "plus")
                .accessibilityLabel("Quick capture")
        }
    }

    private func perform(_ action: PieMenuAction) {
        switch action {
        case .newNote:
            isShowingQuickNote = true
        case .newTodo:
            isShowingNewTodo = true
        case .newWorkItem:
            appRouter.triggerNewWorkItem = true
        case .recordPractice:
            appRouter.triggerRecordPractice = true
        case .newPresentation:
            appRouter.triggerNewPresentation = true
        }
    }
}
