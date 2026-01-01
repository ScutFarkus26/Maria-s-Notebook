// StudentOverviewTab.swift
// Overview tab content extracted from StudentDetailView

import SwiftUI
import SwiftData

struct StudentOverviewTab: View {
    let student: Student
    let isEditing: Bool
    @Binding var draftFirstName: String
    @Binding var draftLastName: String
    @Binding var draftBirthday: Date
    @Binding var draftLevel: Student.Level
    @Binding var draftStartDate: Date
    @Binding var contractsCache: [WorkContract]
    @Binding var selectedContract: WorkContract?
    
    let lessonsByID: [UUID: Lesson]
    let nextLessonsForStudent: [StudentLessonSnapshot]
    
    @Environment(\.modelContext) private var modelContext
    
    private func lessonName(for contract: WorkContract) -> String {
        if let id = UUID(uuidString: contract.lessonID), let lesson = lessonsByID[id] {
            return lesson.name
        }
        return "Lesson"
    }

    var body: some View {
        VStack(spacing: 0) {
            StudentHeaderView(student: student)
                .padding(.top, 36)
            if isEditing {
                StudentEditForm(
                    draftFirstName: $draftFirstName,
                    draftLastName: $draftLastName,
                    draftBirthday: $draftBirthday,
                    draftLevel: $draftLevel,
                    draftStartDate: $draftStartDate
                )
            } else {
                StudentInfoRows(student: student)
                
                Divider()
                    .padding(.top, 8)

                // Working on section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Working on")
                        .font(.headline)
                        .padding(.horizontal, 4)
                    if contractsCache.isEmpty {
                        Text("No active work contracts.")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(contractsCache, id: \.id) { contract in
                            Button(action: {
                                selectedContract = contract
                            }) {
                                ContractRow(contract: contract, lessonName: lessonName(for: contract))
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.vertical, 8)

                Divider()
                    .padding(.top, 8)

                NextLessonsSection(snapshots: nextLessonsForStudent, lessonsByID: lessonsByID)
            }
        }
    }
}

