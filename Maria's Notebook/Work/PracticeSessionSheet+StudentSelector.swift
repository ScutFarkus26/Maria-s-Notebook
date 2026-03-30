import SwiftUI
import SwiftData

// MARK: - Student Selector UI

extension PracticeSessionSheet {

    var studentSelectorSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StudentSelectorSearchBar(searchText: $searchText)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if orderedStudents.isEmpty {
                            emptyPartnersMessage
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            studentSelectionList
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Practice Partners")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showStudentSelector = false
                        searchText = "" // Clear search on dismiss
                    }
                }
            }
        }
    }

    var emptyPartnersMessage: some View {
        Text(searchText.isEmpty ? "No other students have work for this lesson" : "No students match '\(searchText)'")
            .font(AppTheme.ScaledFont.caption)
            .foregroundStyle(.secondary)
            .italic()
            .padding(.vertical, 8)
    }

    var studentSelectionList: some View {
        ForEach(Array(groupedStudents.keys.sorted { $0.rawValue < $1.rawValue }), id: \.rawValue) { category in
            if let students = groupedStudents[category] {
                StudentCategorySection(
                    category: category,
                    students: students,
                    onStudentTap: toggleStudent
                )
            }
        }
    }

    var groupedStudents: [StudentCategory: [CategorizedStudent]] {
        Dictionary(grouping: orderedStudents, by: { $0.category })
    }
}
