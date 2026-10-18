// WorksAgendaView+History.swift
// Each half's History: every presentation given, or every piece of work
// finished.
//
// These were the Presentations and Works logs under Logs, a screen that only
// repeated this one (plan "Simplify the app", Phase 2). They are hosted here
// as they were, paged and filtered as before, and read the workspace's search
// field rather than one of their own. History fills the workspace: the
// Scheduled calendar is where open records are dragged, and nothing in a
// history is dragged anywhere.

import SwiftUI

extension WorksAgendaView {

    /// The list the half on screen is showing.
    var workspaceList: WorkspaceList {
        switch workspaceKind {
        case .presentations: WorkspaceList.resolved(rawValue: presentationsListRaw)
        case .work: WorkspaceList.resolved(rawValue: workListRaw)
        }
    }

    /// The half on screen's choice, remembered per half. Choosing one lets go
    /// of a route's record, as choosing a half does: a focused presentation
    /// makes History load every one ever given to reveal it.
    var workspaceListBinding: Binding<WorkspaceList> {
        Binding(
            get: { workspaceList },
            set: { newValue in
                setList(newValue, for: workspaceKind)
                focusedPresentationID = nil
                focusedWorkID = nil
            }
        )
    }

    var showsHistory: Bool { workspaceList == .history }

    func setList(_ list: WorkspaceList, for kind: WorkspaceKind) {
        switch kind {
        case .presentations: presentationsListRaw = list.rawValue
        case .work: workListRaw = list.rawValue
        }
    }

    /// The half's live list or its History, as a segmented control (Mac
    /// toolbar) or tabs (iPhone and iPad header).
    var workspaceListPicker: some View {
        ScreenViewPicker(
            title: "List",
            selection: workspaceListBinding,
            choices: WorkspaceList.allCases,
            label: { $0.title(in: workspaceKind) }
        )
    }

    /// The finished half of the workspace.
    @ViewBuilder
    var workspaceHistory: some View {
        switch workspaceKind {
        case .presentations:
            LessonAssignmentHistoryView(
                embeddedSearchText: debouncedSearchText,
                focusedAssignmentID: focusedPresentationID
            )
        case .work:
            WorksLogView(
                embeddedSearchText: debouncedSearchText,
                completedOnly: true,
                isEmbedded: true,
                focusedWorkID: focusedWorkID
            )
        }
    }
}
