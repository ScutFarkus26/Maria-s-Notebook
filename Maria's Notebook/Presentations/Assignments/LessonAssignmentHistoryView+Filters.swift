//
//  LessonAssignmentHistoryView+Filters.swift
//  Maria's Notebook
//
//  Filter bar UI for LessonAssignmentHistoryView - extracted for maintainability
//

import SwiftUI
import CoreData

extension LessonAssignmentHistoryView {

    // MARK: - Filter Labels

    var selectedStudentLabel: String {
        if selectedStudentIDs.isEmpty {
            return "All Students"
        } else if selectedStudentIDs.count == 1, let id = selectedStudentIDs.first,
                  let student = safeStudents.first(where: { $0.id == id }) {
            return displayName(for: student)
        } else {
            return "\(selectedStudentIDs.count) Students"
        }
    }

    var selectedAreaLabel: String {
        if selectedAreas.isEmpty {
            return "All Areas"
        } else if selectedAreas.count == 1, let area = selectedAreas.first {
            return area
        } else {
            return "\(selectedAreas.count) Areas"
        }
    }

    // MARK: - Filter Bar

    var filterBar: some View {
        HStack(spacing: 12) {
            // CDStudent Menu (multi-select)
            Menu {
                Button("All Students") { selectedStudentIDs.removeAll() }
                Divider()
                ForEach(safeStudents, id: \.objectID) { student in
                    if let studentID = student.id {
                        Button(action: {
                            if selectedStudentIDs.contains(studentID) {
                                selectedStudentIDs.remove(studentID)
                            } else {
                                selectedStudentIDs.insert(studentID)
                            }
                        }, label: {
                            HStack {
                                if selectedStudentIDs.contains(studentID) {
                                    Image(systemName: "checkmark")
                                }
                                Text(displayName(for: student))
                            }
                        })
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.3")
                    Text(selectedStudentLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
                )
            }

            // Area Menu (multi-select)
            Menu {
                Button("All Areas") { selectedAreas.removeAll() }
                Divider()
                ForEach(availableAreas, id: \.self) { area in
                    Button(action: {
                        if selectedAreas.contains(area) {
                            selectedAreas.remove(area)
                        } else {
                            selectedAreas.insert(area)
                        }
                    }, label: {
                        HStack {
                            if selectedAreas.contains(area) {
                                Image(systemName: "checkmark")
                            }
                            Text(area)
                        }
                    })
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedAreaLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
                )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }
}
