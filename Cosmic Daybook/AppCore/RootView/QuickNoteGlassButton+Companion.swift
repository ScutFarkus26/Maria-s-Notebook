// QuickNoteGlassButton+Companion.swift
// The companion half of the floating button: the panel a long press (or a
// macOS right-click) opens, and where the button can be put.

import SwiftUI

extension QuickNoteGlassButton {

    #if os(macOS)
    /// A left-click opens quick capture, so every other action — the three
    /// companion questions, the five create actions, and placement — lives here.
    @ViewBuilder
    var companionContextMenu: some View {
        Button {
            onAskAI(nil)
        } label: {
            Label("Ask My Notebook", systemImage: "bubble.left.and.text.bubble.right")
        }
        Button {
            onAskAI(companionSnapshot.briefingPrompt)
        } label: {
            Label("Make My Short Plan", systemImage: "list.bullet.clipboard.fill")
        }
        Button {
            onAskAI(NotebookCompanionSnapshot.followUpPrompt)
        } label: {
            Label("Who Needs Follow-up?", systemImage: "person.crop.circle.badge.questionmark")
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
        Button {
            moveCompanionToDesktop()
        } label: {
            Label("Move to Desktop", systemImage: "macwindow.on.rectangle")
        }
        Button(role: .destructive) {
            hideCompanion()
        } label: {
            Label("Hide Companion", systemImage: "eye.slash")
        }
    }
    #endif

    var companionPanel: some View {
        NotebookCompanionPanel(
            snapshot: companionSnapshot,
            isWorking: isAIWorking,
            onPlanDay: {
                performCompanionAction {
                    onAskAI(companionSnapshot.briefingPrompt)
                }
            },
            onFindFollowUps: {
                performCompanionAction {
                    onAskAI(NotebookCompanionSnapshot.followUpPrompt)
                }
            },
            onSuggestPresentations: {
                performCompanionAction {
                    onAskAI(NotebookCompanionSnapshot.presentationPrompt)
                }
            },
            onAskAnything: {
                performCompanionAction {
                    onAskAI(nil)
                }
            },
            onQuickCapture: {
                performCompanionAction {
                    isShowingCommandBar = true
                }
            },
            onReviewTodos: {
                performCompanionAction(action: onReviewTodos)
            },
            placementAction: companionPlacementAction,
            onChangePlacement: companionPlacementHandler,
            onHide: hideCompanion
        )
    }

    var companionAccessibilityLabel: String {
        if isAIWorking {
            return "Notebook companion, checking your notebook"
        }
        if companionSnapshot.attentionCount > 0 {
            return "Notebook companion, \(companionSnapshot.attentionCount) overdue items"
        }
        return "Notebook companion"
    }

    private var companionPlacementAction: NotebookCompanionPanel.PlacementAction? {
        #if os(macOS)
        .moveToDesktop
        #else
        nil
        #endif
    }

    private var companionPlacementHandler: (() -> Void)? {
        #if os(macOS)
        moveCompanionToDesktop
        #else
        nil
        #endif
    }

    func openCompanion() {
        onRefreshCompanion()
        isCompanionPresented = true
    }

    #if os(macOS)
    func moveCompanionToDesktop() {
        isCompanionPresented = false
        isNotebookCompanionDetached = true
        openWindow(id: "notebookCompanion")
    }
    #else
    func moveCompanionToDesktop() {}
    #endif

    func hideCompanion() {
        isCompanionPresented = false
        isNotebookCompanionVisible = false
    }

    private func performCompanionAction(action: @escaping () -> Void) {
        isCompanionPresented = false
        action()
    }
}
