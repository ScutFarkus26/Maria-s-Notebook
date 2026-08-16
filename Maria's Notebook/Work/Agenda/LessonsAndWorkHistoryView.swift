import SwiftUI

/// Keeps completed presentations and completed child work in the same
/// workspace without forcing the guide back into two top-level destinations.
struct LessonsAndWorkHistoryView: View {
    let searchText: String
    let focusedPresentationID: UUID?
    let focusedWorkID: UUID?

    @State private var selection: HistoryKind = .presentations

    var body: some View {
        VStack(spacing: 0) {
            Picker("History", selection: $selection) {
                ForEach(HistoryKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.systemImage).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            switch selection {
            case .presentations:
                LessonAssignmentHistoryView(
                    embeddedSearchText: searchText,
                    focusedAssignmentID: focusedPresentationID
                )
            case .completedWork:
                WorksLogView(
                    embeddedSearchText: searchText,
                    completedOnly: true,
                    isEmbedded: true,
                    focusedWorkID: focusedWorkID
                )
            }
        }
        .onAppear(perform: revealFocusedRecord)
        .onChange(of: focusedPresentationID) { _, _ in revealFocusedRecord() }
        .onChange(of: focusedWorkID) { _, _ in revealFocusedRecord() }
    }

    private func revealFocusedRecord() {
        if focusedWorkID != nil {
            selection = .completedWork
        } else if focusedPresentationID != nil {
            selection = .presentations
        }
    }
}

private extension LessonsAndWorkHistoryView {
    enum HistoryKind: String, CaseIterable, Identifiable {
        case presentations
        case completedWork

        var id: Self { self }

        var title: String {
            switch self {
            case .presentations: "Presentations"
            case .completedWork: "Completed Work"
            }
        }

        var systemImage: String {
            switch self {
            case .presentations: "rectangle.stack"
            case .completedWork: "checkmark.circle"
            }
        }
    }
}
