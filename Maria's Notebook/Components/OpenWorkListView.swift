import SwiftUI
import SwiftData

struct OpenWorkListView: View {
    @Environment(\.modelContext) private var modelContext

    // OPTIMIZATION: Query only open works at database level instead of loading all and filtering in memory
    @Query(
        filter: #Predicate<WorkModel> { $0.statusRaw != "complete" },
        sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)]
    ) private var openWorks: [WorkModel]

    @Query private var lessons: [Lesson]
    @Query private var lessonAssignments: [LessonAssignment]

    @State private var selectedWork: WorkModel?

    // Pagination state
    @State private var pagination = PaginationState(pageSize: 50)

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: Lesson] {
        Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var lessonAssignmentsByID: [UUID: LessonAssignment] {
        Dictionary(lessonAssignments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Paginated open works for display
    private var displayedWorks: [WorkModel] {
        openWorks.paginated(using: pagination)
    }

    private func linkedLessonAssignment(for work: WorkModel) -> LessonAssignment? {
        guard let idString = work.presentationID,
              let id = UUID(uuidString: idString) else { return nil }
        return lessonAssignmentsByID[id]
    }

    private func linkedLesson(for work: WorkModel) -> Lesson? {
        // Priority 1: Try WorkModel.lessonID directly (most reliable)
        if !work.lessonID.isEmpty, let lessonID = UUID(uuidString: work.lessonID) {
            if let lesson = lessonsByID[lessonID] {
                return lesson
            }
        }
        
        // Priority 2: Try through LessonAssignment relationship
        if let la = linkedLessonAssignment(for: work) {
            // Use lesson relationship if available
            if let lesson = la.lesson {
                return lesson
            }
            
            // Fallback: Convert LessonAssignment.lessonID to UUID for lookup
            if let lessonIDUUID = la.lessonIDUUID {
                return lessonsByID[lessonIDUUID]
            }
        }
        
        return nil
    }

    private func workTitle(_ work: WorkModel) -> String {
        let title = work.title.trimmed()
        if !title.isEmpty { return title }
        
        // Use kind for type label
        let typeLabel = (work.kind ?? .research).displayName
        
        if let lesson = linkedLesson(for: work) { return "\(typeLabel): \(lesson.name)" }
        return typeLabel
    }

    private func workSubtitle(_ work: WorkModel) -> String {
        let date: Date = {
            if let la = linkedLessonAssignment(for: work) {
                return la.presentedAt ?? la.scheduledFor ?? la.createdAt
            }
            return work.createdAt
        }()
        let dateString = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        if let lesson = linkedLesson(for: work) {
            let subject = lesson.subject.trimmed()
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
        NavigationStack {
            List {
                ForEach(displayedWorks) { work in
                    let openCount = (work.participants ?? []).filter { $0.completedAt == nil }.count
                    WorkCard.list(
                        work: work,
                        title: workTitle(work),
                        subtitle: workSubtitle(work),
                        badge: openCount > 0 ? .openCount(openCount) : nil,
                        onOpen: { w in selectedWork = w }
                    )
                }

                // Pagination footer
                if pagination.totalCount > 0 {
                    Section {
                        PaginatedListFooter(state: pagination, itemName: "open works")
                    }
                }
            }
            .navigationTitle("Open Work")
            .onChange(of: openWorks.count) { _, newCount in
                pagination.updateTotal(newCount)
            }
            .onAppear {
                pagination.updateTotal(openWorks.count)
            }
        }
        // Fix: Use 'isPresented' to avoid ambiguity between standard
        // 'sheet(item:)' and 'SheetPresentationHelpers' extension
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
    Text("OpenWorkListView requires live data")
}
