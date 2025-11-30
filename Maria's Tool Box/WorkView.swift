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

    @AppStorage("WorkView.selectedWorkType") private var workSelectedTypeRaw: String = ""
    @AppStorage("WorkView.selectedSubject") private var workSelectedSubjectRaw: String = ""

    private var selectedWorkType: WorkModel.WorkType? {
        WorkModel.WorkType(rawValue: workSelectedTypeRaw)
    }

    private var selectedSubject: String? {
        workSelectedSubjectRaw.isEmpty ? nil : workSelectedSubjectRaw
    }

    private var subjects: [String] {
        let existing = Array(Set(lessons
            .map { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        )).sorted()
        return FilterOrderStore.loadSubjectOrder(existing: existing)
    }

    private var filteredWorks: [WorkModel] {
        var base = workItems
        if let type = selectedWorkType {
            base = base.filter { $0.workType == type }
        }
        if let subject = selectedSubject {
            base = base.filter { work in
                guard let slID = work.studentLessonID, let sl = studentLessonsByID[slID], let lesson = lessonsByID[sl.lessonID] else { return false }
                return lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(subject) == .orderedSame
            }
        }
        return base
    }

    // Helper maps for quick lookup
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }
    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentLessonsByID: [UUID: StudentLesson] { Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) }) }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Work Type")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            SidebarFilterButton(
                icon: "square.grid.2x2",
                title: "All Types",
                color: .accentColor,
                isSelected: selectedWorkType == nil
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workSelectedTypeRaw = ""
                }
            }

            SidebarFilterButton(
                icon: "magnifyingglass.circle.fill",
                title: WorkModel.WorkType.research.rawValue,
                color: .teal,
                isSelected: selectedWorkType == .research
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workSelectedTypeRaw = WorkModel.WorkType.research.rawValue
                }
            }

            SidebarFilterButton(
                icon: "arrow.triangle.2.circlepath.circle.fill",
                title: WorkModel.WorkType.followUp.rawValue,
                color: .orange,
                isSelected: selectedWorkType == .followUp
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workSelectedTypeRaw = WorkModel.WorkType.followUp.rawValue
                }
            }

            SidebarFilterButton(
                icon: "hammer.fill",
                title: WorkModel.WorkType.practice.rawValue,
                color: .purple,
                isSelected: selectedWorkType == .practice
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workSelectedTypeRaw = WorkModel.WorkType.practice.rawValue
                }
            }

            Text("Subject")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            SidebarFilterButton(
                icon: "rectangle.3.group",
                title: "All Subjects",
                color: .accentColor,
                isSelected: selectedSubject == nil
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    workSelectedSubjectRaw = ""
                }
            }

            ForEach(subjects, id: \.self) { subject in
                SidebarFilterButton(
                    icon: "folder.fill",
                    title: subject,
                    color: AppColors.color(forSubject: subject),
                    isSelected: selectedSubject?.caseInsensitiveCompare(subject) == .orderedSame
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        workSelectedSubjectRaw = subject
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.leading, 16)
        .frame(width: 200, alignment: .topLeading)
        .background(Color.gray.opacity(0.08))
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                sidebar

                Divider()

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
                    } else if filteredWorks.isEmpty {
                        VStack(spacing: 8) {
                            Text("No work matches your filters")
                                .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                            Text("Try adjusting the filters on the left.")
                                .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
#if os(macOS)
                        WorkCardsGridView(
                            works: filteredWorks,
                            studentsByID: studentsByID,
                            lessonsByID: lessonsByID,
                            studentLessonsByID: studentLessonsByID,
                            onTapWork: { work in
                                openWindow(id: "WorkDetailWindow", value: work.id)
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
#else
                        WorkCardsGridView(
                            works: filteredWorks,
                            studentsByID: studentsByID,
                            lessonsByID: lessonsByID,
                            studentLessonsByID: studentLessonsByID,
                            onTapWork: { work in
                                selectedWorkID = work.id
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
            }
            .navigationTitle("Work")
        }
        .sheet(isPresented: $isPresentingAddWork) {
            AddWorkView {
                isPresentingAddWork = false
            }
        }
#if !os(macOS)
        .sheet(isPresented: Binding(get: { selectedWorkID != nil }, set: { if !$0 { selectedWorkID = nil } })) {
            if let id = selectedWorkID, let work = workItems.first(where: { $0.id == id }) {
                WorkDetailView(work: work) {
                    selectedWorkID = nil
                }
            } else {
                EmptyView()
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
