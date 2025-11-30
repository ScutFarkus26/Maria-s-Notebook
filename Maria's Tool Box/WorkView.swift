import SwiftUI
import SwiftData

struct WorkView: View {
    @Environment(\.modelContext) private var modelContext

    // Data sources
    @Query(sort: [
        SortDescriptor(\Student.lastName),
        SortDescriptor(\Student.firstName)
    ]) private var students: [Student]

    @Query(sort: \StudentLesson.createdAt, order: .forward) private var studentLessons: [StudentLesson]
    @Query(sort: \Lesson.name, order: .forward) private var lessons: [Lesson]
    @Query(sort: \WorkModel.createdAt, order: .reverse) private var workItems: [WorkModel]

    // Add Work sheet state
    @State private var isPresentingAddWork = false
    @State private var selectedStudents = Set<UUID>()
    @State private var selectedWorkType: WorkModel.WorkType = .research
    @State private var selectedLessonID: UUID? = nil
    @State private var notesText: String = ""

    // Helper maps for quick lookup
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }
    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentLessonsByID: [UUID: StudentLesson] { Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) }) }

    var body: some View {
        NavigationStack {
            Group {
                if workItems.isEmpty {
                    VStack(spacing: 8) {
                        Text("No work yet")
                            .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                        Text("Click the plus button to add work.")
                            .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    WorkCardsGridView(
                        works: workItems,
                        studentsByID: studentsByID,
                        lessonsByID: lessonsByID,
                        studentLessonsByID: studentLessonsByID,
                        onTapWork: { _ in }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Button {
                    resetForm()
                    isPresentingAddWork = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: AppTheme.FontSize.titleXLarge))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .padding()
            }
            .navigationTitle("Work")
        }
        .sheet(isPresented: $isPresentingAddWork) {
            NavigationStack {
                Form {
                    Section("Select Students") {
                        if students.isEmpty {
                            Text("No students available")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(students) { student in
                                MultipleSelectionRow(
                                    title: student.fullName,
                                    isSelected: selectedStudents.contains(student.id)
                                ) {
                                    if selectedStudents.contains(student.id) {
                                        selectedStudents.remove(student.id)
                                    } else {
                                        selectedStudents.insert(student.id)
                                    }
                                }
                            }
                        }
                    }

                    Section("Work Type") {
                        Picker("Work Type", selection: $selectedWorkType) {
                            ForEach(WorkModel.WorkType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Linked Lesson (optional)") {
                        Picker("Lesson", selection: $selectedLessonID) {
                            Text("None").tag(UUID?.none)
                            ForEach(studentLessons) { sl in
                                let lessonName = lessonsByID[sl.lessonID]?.name ?? "Lesson"
                                let date = sl.scheduledFor ?? sl.givenAt ?? sl.createdAt
                                Text("\(lessonName) • \(date.formatted(date: .numeric, time: .omitted))")
                                    .tag(Optional(sl.id))
                            }
                        }
                    }

                    Section("Notes") {
                        TextEditor(text: $notesText)
                            .frame(minHeight: 100)
                    }
                }
                .navigationTitle("Add Work")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresentingAddWork = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveWork() }
                            .disabled(selectedStudents.isEmpty)
                    }
                }
            }
        }
    }

    private func resetForm() {
        selectedStudents = []
        selectedWorkType = .research
        selectedLessonID = nil
        notesText = ""
    }

    private func saveWork() {
        guard !selectedStudents.isEmpty else { return }
        let newWork = WorkModel(
            studentIDs: Array(selectedStudents),
            workType: selectedWorkType,
            studentLessonID: selectedLessonID,
            notes: notesText.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date()
        )
        modelContext.insert(newWork)
        isPresentingAddWork = false
    }
}

fileprivate struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
