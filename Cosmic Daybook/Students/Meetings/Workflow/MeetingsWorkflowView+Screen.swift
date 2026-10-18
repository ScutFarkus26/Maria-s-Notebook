// MeetingsWorkflowView+Screen.swift
// The Meetings screen's Queue / History switch, and the history it shows.
//
// Split from the view for SwiftLint's type-length limit; the state these read
// is declared in MeetingsWorkflowView.swift.

import SwiftUI

extension MeetingsWorkflowView {

    var screenView: MeetingsScreenView {
        MeetingsScreenView.resolved(rawValue: screenViewRaw)
    }

    /// The queue or the history. On the Mac the switch is in the toolbar; on
    /// iPhone and iPad it heads the page, above the queue's own column.
    @ViewBuilder
    func screen(
        queue: MeetingQueueArrangement,
        byID: [UUID: CDStudent],
        rows: @escaping ([UUID]) -> [CDStudent]
    ) -> some View {
        #if os(macOS)
        screenContent(queue: queue, byID: byID, rows: rows)
        #else
        VStack(spacing: 0) {
            screenViewPicker
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.small)
            Divider()
            screenContent(queue: queue, byID: byID, rows: rows)
        }
        #endif
    }

    @ViewBuilder
    private func screenContent(
        queue: MeetingQueueArrangement,
        byID: [UUID: CDStudent],
        rows: @escaping ([UUID]) -> [CDStudent]
    ) -> some View {
        switch screenView {
        case .queue:
            content(queue: queue, byID: byID, rows: rows)
        case .history:
            // Every child's meetings, read with this screen's search field.
            MeetingsLogView(embeddedSearchText: searchText)
                .padding(.top, AppTheme.Spacing.small)
        }
    }

    var screenViewPicker: some View {
        ScreenViewPicker(
            title: "View",
            selection: Binding(get: { screenView }, set: { screenViewRaw = $0.rawValue }),
            choices: MeetingsScreenView.allCases,
            label: \.title
        )
    }
}
