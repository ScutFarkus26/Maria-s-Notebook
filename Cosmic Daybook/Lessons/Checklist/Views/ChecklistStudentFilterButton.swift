//
//  ChecklistStudentFilterButton.swift
//  Cosmic Daybook
//
//  The checklist's student filter: a button that opens the student picker and says
//  how many columns are showing. The iPhone's filter bar reads "All Students"; the
//  Mac and iPad toolbar reads "All 22" or "5 of 22".
//

import SwiftUI

struct ChecklistStudentFilterButton: View {
    @Binding var studentFilterIDs: Set<UUID>
    /// Every student available to filter to — already narrowed to the enrolled,
    /// non-test roster by the caller.
    let rosterStudents: [CDStudent]
    var isToolbarItem = false

    @State private var isShowingStudentPicker = false

    private var title: String {
        if studentFilterIDs.isEmpty {
            return isToolbarItem ? "All \(rosterStudents.count)" : "All Students"
        }
        return "\(studentFilterIDs.count) of \(rosterStudents.count)"
    }

    var body: some View {
        Button {
            isShowingStudentPicker = true
        } label: {
            if isToolbarItem {
                // A toolbar draws a Label as its icon alone; the count is the point here.
                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                    Text(title)
                }
                .lineLimit(1)
            } else {
                Label(title, systemImage: "person.2")
                    .lineLimit(1)
            }
        }
        .help("Show only the students you pick")
        .accessibilityLabel(
            studentFilterIDs.isEmpty
                ? "Filter students, all students shown"
                : "Filter students, \(studentFilterIDs.count) of \(rosterStudents.count) shown"
        )
        .popover(isPresented: $isShowingStudentPicker, arrowEdge: .bottom) {
            StudentPickerPopover(
                students: rosterStudents,
                selectedIDs: $studentFilterIDs,
                onDone: { isShowingStudentPicker = false },
                allowsCreatingStudents: false
            )
        }
    }
}
