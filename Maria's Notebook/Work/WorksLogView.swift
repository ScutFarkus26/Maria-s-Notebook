import SwiftUI
import SwiftData

struct WorksLogView: View {
    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)])
    private var allWorks: [WorkModel]

    @Query private var lessons: [Lesson]
    @Query private var studentLessons: [StudentLesson]

    @State private var selectedWork: WorkModel? = nil

    // Pagination state
    @StateObject private var pagination = PaginationState(pageSize: 50)

    private var lessonsByID: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }

    private var studentLessonsByID: [UUID: StudentLesson] {
        Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })
    }

    /// Paginated works for display
    private var displayedWorks: [WorkModel] {
        allWorks.paginated(using: pagination)
    }

    private func linkedStudentLesson(for work: WorkModel) -> StudentLesson? {
        guard let id = work.studentLessonID else { return nil }
        return studentLessonsByID[id]
    }

    private func linkedLesson(for work: WorkModel) -> Lesson? {
        guard let sl = linkedStudentLesson(for: work) else { return nil }
        // CloudKit compatibility: Convert String lessonID to UUID for lookup
        guard let lessonIDUUID = UUID(uuidString: sl.lessonID) else { return nil }
        return lessonsByID[lessonIDUUID]
    }

    private func workTitle(_ work: WorkModel) -> String {
        let title = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let lesson = linkedLesson(for: work) { return "\(work.workType.rawValue): \(lesson.name)" }
        return work.workType.rawValue
    }

    private func workSubtitle(_ work: WorkModel) -> String {
        let date: Date = {
            if let sl = linkedStudentLesson(for: work) {
                return sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
            }
            return work.createdAt
        }()
        let dateString = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        if let lesson = linkedLesson(for: work) {
            let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            return subject.isEmpty ? dateString : "\(subject) • \(dateString)"
        }
        return dateString
    }

    @ViewBuilder
    private func workDetailSheetContent(for work: WorkModel) -> some View {
        WorkDetailView(workID: work.id, onDone: {
            selectedWork = nil
        })
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 640)
        .presentationSizingFitted()
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    var body: some View {
        List {
            ForEach(displayedWorks) { work in
                WorkCard.list(
                    work: work,
                    title: workTitle(work),
                    subtitle: workSubtitle(work),
                    badge: .status(work.isOpen ? "active" : "complete"),
                    onOpen: { w in selectedWork = w }
                )
            }

            // Pagination footer
            if pagination.totalCount > 0 {
                Section {
                    PaginatedListFooter(state: pagination, itemName: "works")
                }
            }
        }
        .navigationTitle("Works Log")
        .onChange(of: allWorks.count) { _, newCount in
            pagination.updateTotal(newCount)
        }
        .onAppear {
            pagination.updateTotal(allWorks.count)
        }
        .sheet(isPresented: Binding(
            get: { selectedWork != nil },
            set: { if !$0 { selectedWork = nil } }
        )) {
            if let work = selectedWork {
                workDetailSheetContent(for: work)
            }
        }
    }
}

#Preview {
    WorksLogView()
        .modelContainer(PreviewEnvironment.previewContainer(for: [WorkModel.self, Lesson.self, StudentLesson.self]))
}
