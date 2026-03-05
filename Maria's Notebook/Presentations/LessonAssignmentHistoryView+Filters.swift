//
//  LessonAssignmentHistoryView+Filters.swift
//  Maria's Notebook
//
//  Filter bar UI for LessonAssignmentHistoryView - extracted for maintainability
//

import SwiftUI
import SwiftData

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

    var selectedSubjectLabel: String {
        if selectedSubjects.isEmpty {
            return "All Subjects"
        } else if selectedSubjects.count == 1, let subject = selectedSubjects.first {
            return subject
        } else {
            return "\(selectedSubjects.count) Subjects"
        }
    }

    // MARK: - Filter Bar

    var filterBar: some View {
        HStack(spacing: 12) {
            // Student Menu (multi-select)
            Menu {
                Button("All Students") { selectedStudentIDs.removeAll() }
                Divider()
                ForEach(safeStudents) { student in
                    Button(action: {
                        if selectedStudentIDs.contains(student.id) {
                            selectedStudentIDs.remove(student.id)
                        } else {
                            selectedStudentIDs.insert(student.id)
                        }
                    }, label: {
                        HStack {
                            if selectedStudentIDs.contains(student.id) {
                                Image(systemName: "checkmark")
                            }
                            Text(displayName(for: student))
                        }
                    })
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.3")
                    Text(selectedStudentLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            // Subject Menu (multi-select)
            Menu {
                Button("All Subjects") { selectedSubjects.removeAll() }
                Divider()
                ForEach(availableSubjects, id: \.self) { subject in
                    Button(action: {
                        if selectedSubjects.contains(subject) {
                            selectedSubjects.remove(subject)
                        } else {
                            selectedSubjects.insert(subject)
                        }
                    }, label: {
                        HStack {
                            if selectedSubjects.contains(subject) {
                                Image(systemName: "checkmark")
                            }
                            Text(subject)
                        }
                    })
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedSubjectLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }
}
