// QuietStudentsRail.swift
// The column of children who have gone longest without the guide looking at
// their work, beside the work you could look at.
//
// The Work half's counterpart to `WaitingStudentsRail`, in the same corner,
// drawn by the same `WaitingStudentsColumn`. It is not the same list wearing a
// new label: this one is about the child rather than the item, and the top of
// it is the children carrying no open work at all — the one thing the grid
// beside it structurally cannot show, because a child with nothing has no card.
//
// Tapping a name narrows the work beside it, exactly as tapping one narrows the
// lessons on the other side of the workspace.

import CoreData
import SwiftUI

struct QuietStudentsRail: View {
    /// The enrolled roster, not just the children who happen to own work — the
    /// children with none are the point of the list.
    let students: [CDStudent]
    /// School days since the guide last touched anything of each child's, built
    /// once per refresh by the workspace.
    let daysSinceTouchByStudent: [UUID: Int]
    let studentIDsWithOpenWork: Set<UUID>
    let searchText: String
    @Binding var selectedStudentID: UUID?

    @SceneStorage("Work.quietScope")
    private var scopeRaw: String = QuietStudentsScope.everyone.rawValue

    private var scope: QuietStudentsScope {
        QuietStudentsScope.resolved(rawValue: scopeRaw)
    }

    private var scopeBinding: Binding<QuietStudentsScope> {
        Binding(
            get: { scope },
            set: { newValue in
                adaptiveWithAnimation(.easeInOut(duration: 0.15)) { scopeRaw = newValue.rawValue }
            }
        )
    }

    private var entries: [WaitingStudent] {
        QuietStudentsOrder.ordered(
            students: students,
            daysSinceTouch: daysSinceTouchByStudent,
            studentIDsWithOpenWork: studentIDsWithOpenWork,
            scope: scope,
            search: searchText
        )
    }

    var body: some View {
        WaitingStudentsColumn(
            vocabulary: .work,
            entries: entries,
            selectedStudentID: selectedStudentID,
            onSelect: select
        ) {
            Picker("Show", selection: scopeBinding) {
                ForEach(QuietStudentsScope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Everyone, or only children carrying no open work")
        } emptyState: {
            emptyStateMessage
        }
    }

    @ViewBuilder
    private var emptyStateMessage: some View {
        if !searchText.trimmed().isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if scope == .withoutWork {
            ContentUnavailableView(
                "Everyone Has Work",
                systemImage: "checkmark.circle",
                description: Text("Every child is carrying something.")
            )
        } else {
            ContentUnavailableView(
                "No Children Yet",
                systemImage: "person.2",
                description: Text("Enrolled children appear here, quietest first.")
            )
        }
    }

    /// Tapping a child narrows the work beside the rail to that child, and
    /// tapping them again clears it — the same gesture, and the same way out, as
    /// the Presentations rail.
    private func select(_ student: CDStudent) {
        guard let id = student.id else { return }
        adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
            selectedStudentID = selectedStudentID == id ? nil : id
        }
    }
}
