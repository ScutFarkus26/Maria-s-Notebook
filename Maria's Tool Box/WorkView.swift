import SwiftUI
import SwiftData

struct WorkView: View {
    @Environment(\.modelContext) private var modelContext

#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

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
    @State private var selectedWorkID: UUID? = nil
    @State private var selectedWork: WorkModel? = nil

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
#if os(macOS)
                    WorkCardsGridView(
                        works: workItems,
                        studentsByID: studentsByID,
                        lessonsByID: lessonsByID,
                        studentLessonsByID: studentLessonsByID,
                        onTapWork: { work in
#if os(macOS)
                            openWindow(id: "WorkDetailWindow", value: work.id)
#else
                            selectedWork = work
#endif
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
#else
                    WorkCardsGridView(
                        works: workItems,
                        studentsByID: studentsByID,
                        lessonsByID: lessonsByID,
                        studentLessonsByID: studentLessonsByID,
                        onTapWork: { work in
#if os(macOS)
                            openWindow(id: "WorkDetailWindow", value: work.id)
#else
                            selectedWork = work
#endif
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Button {
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
            AddWorkView {
                isPresentingAddWork = false
            }
        }
#if !os(macOS)
        .sheet(item: $selectedWork) { work in
            WorkDetailView(work: work) {
                selectedWork = nil
            }
        }
#endif
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
