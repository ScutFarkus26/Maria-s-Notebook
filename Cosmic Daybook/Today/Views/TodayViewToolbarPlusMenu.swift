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
            Divider()
            // The pad's section hides itself while the pad is empty, so this
            // is how a blank page is reached on a day that has nothing on it.
            Button {
                adaptiveWithAnimation(.snappy(duration: 0.2)) {
                    isDayPadExpanded = true
                }
            } label: {
                Label("Today's Pad", systemImage: "note.text")
            }
        } label: {
            Image(systemName: "plus")
                .accessibilityLabel("Quick capture")
        }
    }

    private func perform(_ action: PieMenuAction) {
        switch action {
        case .newNote:
            activeSheet = .quickNote(studentIDs: nil)
        case .newTodo:
            activeSheet = .newTodo
        case .newWorkItem:
            appRouter.triggerNewWorkItem = true
        case .recordPractice:
            appRouter.triggerRecordPractice = true
        case .newPresentation:
            appRouter.triggerNewPresentation = true
        }
    }
}
