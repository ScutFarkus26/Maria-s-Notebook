// TodayViewToolbarPlusMenu.swift
// Toolbar `+` menu for the Today view — quick capture plus the five create
// actions, in thumb-reach at the top of the screen. On iPhone, and whenever the
// floating companion is hidden, this is the way to the five actions.

import SwiftUI

extension TodayView {

    @ViewBuilder
    var toolbarPlusMenu: some View {
        Menu {
            Button {
                appRouter.triggerCommandBar = true
            } label: {
                Label("Capture…", systemImage: "waveform.badge.mic")
            }
            Divider()
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
