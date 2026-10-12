// TodayViewToolbarPlusMenu.swift
// Toolbar `+` menu for the Today view — quick capture plus the five create
// actions, in thumb-reach at the top of the screen. On iOS, and whenever the
// floating quick-capture button is hidden, this is the way to the five actions.
// The sheets RootView owns open through this window's `QuickCaptureActions`,
// not the router's shared flags, which every main window obeyed.

import SwiftUI

extension TodayView {

    @ViewBuilder
    var toolbarPlusMenu: some View {
        Menu {
            TodayQuickCaptureButton(title: "Capture…", systemImage: "waveform.badge.mic") {
                $0?.openCommandBar()
            }
            Divider()
            ForEach(PieMenuAction.allCases, id: \.self) { action in
                switch action {
                case .newNote:
                    Button {
                        activeSheet = .quickNote(studentIDs: nil)
                    } label: {
                        Label(action.label, systemImage: action.icon)
                    }
                case .newTodo:
                    Button {
                        activeSheet = .newTodo
                    } label: {
                        Label(action.label, systemImage: action.icon)
                    }
                case .newWorkItem, .recordPractice, .newPresentation:
                    TodayQuickCaptureButton(title: action.label, systemImage: action.icon) {
                        $0?.perform(action)
                    }
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
}

/// A `+` menu item that runs in this window: reads the window's
/// `QuickCaptureActions` from the environment (an extension of `TodayView`
/// can't add the property itself).
private struct TodayQuickCaptureButton: View {
    let title: String
    let systemImage: String
    let action: (QuickCaptureActions?) -> Void
    @Environment(\.quickCaptureActions) private var quickCapture

    var body: some View {
        Button {
            action(quickCapture)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
