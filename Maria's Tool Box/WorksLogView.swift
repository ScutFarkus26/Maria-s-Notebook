import SwiftUI
import SwiftData

struct WorksLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize

    @Query(sort: [
        SortDescriptor(\Student.lastName),
        SortDescriptor(\Student.firstName)
    ]) private var students: [Student]

    @Query(sort: \StudentLesson.createdAt, order: .forward) private var studentLessons: [StudentLesson]
    @Query(sort: \Lesson.name, order: .forward) private var lessons: [Lesson]
    @Query(sort: \WorkModel.createdAt, order: .reverse) private var workItems: [WorkModel]

    @State private var filters = WorkFilters()
    @State private var isShowingStudentFilterPopover = false
    @State private var selectedWorkID: UUID? = nil
    @State private var showingAddWork: Bool = false

    @SceneStorage("WorksLogView.selectedSubject") private var selectedSubjectStorage: String = ""
    @SceneStorage("WorksLogView.selectedStudentIDs") private var selectedStudentIDsStorage: String = ""
    @SceneStorage("WorksLogView.searchText") private var searchTextStorage: String = ""
    @SceneStorage("WorksLogView.grouping") private var groupingStorage: String = ""
    @SceneStorage("WorksLogView.level") private var levelStorage: String = "All"

    private var lookupService: WorkLookupService { WorkLookupService(students: students, lessons: lessons, studentLessons: studentLessons) }

    private var filteredWorks: [WorkModel] {
        filters.filterWorks(
            workItems,
            studentLessonsByID: lookupService.studentLessonsByID,
            lessonsByID: lookupService.lessonsByID
        )
    }

    private func syncFiltersFromStorage() {
        if let grouping = WorkFilters.Grouping(rawValue: groupingStorage) { filters.grouping = grouping }
        filters.selectedSubject = selectedSubjectStorage.isEmpty ? nil : selectedSubjectStorage
        filters.searchText = searchTextStorage
        let parts = selectedStudentIDsStorage.split(separator: ",").map { String($0) }
        let uuids = parts.compactMap { UUID(uuidString: $0) }
        filters.selectedStudentIDs = Set(uuids)
        if let level = WorkFilters.LevelFilter(rawValue: levelStorage) { filters.level = level }
    }

    private func syncFiltersToStorage() {
        groupingStorage = filters.grouping.rawValue
        selectedSubjectStorage = filters.selectedSubject ?? ""
        searchTextStorage = filters.searchText
        selectedStudentIDsStorage = filters.selectedStudentIDs.map { $0.uuidString }.joined(separator: ",")
        levelStorage = filters.level.rawValue
    }

    @ViewBuilder
    private var content: some View {
        if workItems.isEmpty {
            WorkEmptyStateView(type: .noWork)
        } else if filteredWorks.isEmpty {
            WorkEmptyStateView(type: .noMatchingFilters)
        } else {
            WorkContentView(
                works: filteredWorks,
                grouping: filters.grouping,
                lookupService: lookupService,
                onTapWork: { (work: WorkModel) in
                    selectedWorkID = work.id
                },
                onToggleComplete: { (work: WorkModel) in
                    work.completedAt = work.isCompleted ? nil : Date()
                    try? modelContext.save()
                }
            )
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            WorkViewSidebar(
                filters: $filters,
                isShowingStudentFilterPopover: $isShowingStudentFilterPopover,
                subjects: lookupService.subjects,
                students: students,
                displayName: lookupService.displayName
            )

            Divider()

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    showingAddWork = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: AppTheme.FontSize.titleXLarge))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: [.command, .option])
                .padding()
            }
        }
        .sheet(isPresented: Binding(get: { selectedWorkID != nil }, set: { if !$0 { selectedWorkID = nil } })) {
            if let id = selectedWorkID {
                WorkDetailContainerView(workID: id) {
                    selectedWorkID = nil
                }
#if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizing(.fitted)
#else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
#endif
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showingAddWork) {
            AddWorkView(onDone: {
                showingAddWork = false
            })
#if os(macOS)
            .frame(minWidth: 560, minHeight: 560)
            .presentationSizing(.fitted)
#else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
#endif
        }
        .onAppear {
            syncFiltersFromStorage()
            WorkDataMaintenance.backfillParticipantsIfNeeded(using: modelContext)
        }
        .onChange(of: filters.grouping) { _, _ in syncFiltersToStorage() }
        .onChange(of: filters.selectedSubject) { _, _ in syncFiltersToStorage() }
        .onChange(of: filters.searchText) { _, _ in syncFiltersToStorage() }
        .onChange(of: filters.selectedStudentIDs) { _, _ in syncFiltersToStorage() }
        .onChange(of: filters.level) { _, _ in syncFiltersToStorage() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewWorkRequested"))) { _ in
            showingAddWork = true
        }
    }
}

#Preview {
    WorksLogView()
}
