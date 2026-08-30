// QuietStudentsStrip.swift
// The quiet list on a phone: one scrolling row of names above the work.
//
// The Work half's counterpart to `WaitingStudentsStrip`, drawn by the same
// `WaitingStudentsBar`. A phone has no room for the column, and the alternative
// — leaving the Work half without one — would mean the two halves of the
// workspace answered different questions depending on the device.

import CoreData
import SwiftUI

struct QuietStudentsStrip: View {
    let students: [CDStudent]
    let daysSinceTouchByStudent: [UUID: Int]
    let studentIDsWithOpenWork: Set<UUID>
    let searchText: String
    @Binding var selectedStudentID: UUID?

    @SceneStorage("Work.quietScope")
    private var scopeRaw: String = QuietStudentsScope.everyone.rawValue

    private var scope: QuietStudentsScope {
        QuietStudentsScope.resolved(rawValue: scopeRaw)
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
        WaitingStudentsBar(
            vocabulary: .work,
            entries: entries,
            selectedStudentID: selectedStudentID,
            emptyMessage: scope == .withoutWork ? "Everyone has work" : "No children yet",
            onSelect: select
        ) {
            scopeMenu
        } expanded: {
            QuietStudentsRail(
                students: students,
                daysSinceTouchByStudent: daysSinceTouchByStudent,
                studentIDsWithOpenWork: studentIDsWithOpenWork,
                searchText: searchText,
                selectedStudentID: $selectedStudentID
            )
        }
    }

    private var scopeMenu: some View {
        Menu {
            Picker("Show", selection: Binding(
                get: { scope },
                set: { scopeRaw = $0.rawValue }
            )) {
                ForEach(QuietStudentsScope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Label(scope.title, systemImage: "line.3.horizontal.decrease.circle")
                .font(AppTheme.ScaledFont.captionSemibold)
                .labelStyle(.titleAndIcon)
        }
        .accessibilityLabel("Showing \(scope.title)")
    }

    private func select(_ student: CDStudent) {
        guard let id = student.id else { return }
        adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
            selectedStudentID = selectedStudentID == id ? nil : id
        }
    }
}
