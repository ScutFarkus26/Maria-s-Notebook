import SwiftUI
import SwiftData

struct WorkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize

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

    // UI state
    @State private var filters = WorkFilters()
    @State private var isPresentingAddWork = false
    @State private var selectedWorkID: UUID? = nil
    @State private var isShowingStudentFilterPopover = false

    // Scene storage for persistence
    @SceneStorage("WorkView.selectedSubject") private var selectedSubjectStorage: String = ""
    @SceneStorage("WorkView.selectedStudentIDs") private var selectedStudentIDsStorage: String = ""
    @SceneStorage("WorkView.searchText") private var searchTextStorage: String = ""
    @SceneStorage("WorkView.grouping") private var groupingStorage: String = "none"
    
    // Lookup service
    private var lookupService: WorkLookupService {
        WorkLookupService(
            students: students,
            lessons: lessons,
            studentLessons: studentLessons
        )
    }
    
    // Filtered works using the filter object
    private var filteredWorks: [WorkModel] {
        filters.filterWorks(
            workItems,
            studentLessonsByID: lookupService.studentLessonsByID,
            lessonsByID: lookupService.lessonsByID
        )
    }

    // Sync filters with scene storage
    private func syncFiltersFromStorage() {
        if let grouping = WorkFilters.Grouping(rawValue: groupingStorage) {
            filters.grouping = grouping
        }
        filters.selectedSubject = selectedSubjectStorage.isEmpty ? nil : selectedSubjectStorage
        filters.searchText = searchTextStorage
        
        // Parse student IDs
        let parts = selectedStudentIDsStorage.split(separator: ",").map { String($0) }
        let uuids = parts.compactMap { UUID(uuidString: $0) }
        filters.selectedStudentIDs = Set(uuids)
    }
    
    private func syncFiltersToStorage() {
        groupingStorage = filters.grouping.rawValue
        selectedSubjectStorage = filters.selectedSubject ?? ""
        searchTextStorage = filters.searchText
        selectedStudentIDsStorage = filters.selectedStudentIDs.map { $0.uuidString }.joined(separator: ",")
    }
    
    private func handleWorkSelection(_ work: WorkModel) {
        #if os(macOS)
        openWindow(id: "WorkDetailWindow", value: work.id)
        #else
        selectedWorkID = work.id
        #endif
    }
    
    private func handleToggleComplete(_ work: WorkModel) {
        work.completedAt = work.isCompleted ? nil : Date()
        do { try modelContext.save() } catch { }
    }

#if !os(macOS)
    private var filtersMenu: some View {
        Menu {
            Section("Students") {
                Button("Select Students…") { isShowingStudentFilterPopover = true }
                Button("Clear Selected") { filters.selectedStudentIDs = [] }
            }
            Section("Subject") {
                Button("All Subjects") { filters.selectedSubject = nil }
                ForEach(lookupService.subjects, id: \.self) { subject in
                    Button(subject) { filters.selectedSubject = subject }
                }
            }
            Section("Group By") {
                ForEach(WorkFilters.Grouping.allCases, id: \.self) { grouping in
                    Button(grouping.displayName) { filters.grouping = grouping }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }
#endif

    var body: some View {
        mainContent
            .sheet(isPresented: $isPresentingAddWork) {
                AddWorkView {
                    isPresentingAddWork = false
                }
            }
            .onAppear {
                syncFiltersFromStorage()
            }
            .onChange(of: filters.grouping) { _, _ in syncFiltersToStorage() }
            .onChange(of: filters.selectedSubject) { _, _ in syncFiltersToStorage() }
            .onChange(of: filters.searchText) { _, _ in syncFiltersToStorage() }
            .onChange(of: filters.selectedStudentIDs) { _, _ in syncFiltersToStorage() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewWorkRequested"))) { _ in
                isPresentingAddWork = true
            }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        NavigationStack {
            layoutContent
        }
#if !os(macOS)
        .toolbar {
            if hSize == .compact {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAddWork = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    filtersMenu
                }
            }
        }
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
    
    @ViewBuilder
    private var layoutContent: some View {
#if os(macOS)
        regularLayout
#else
        if hSize == .compact {
            compactLayout
        } else {
            regularLayout
        }
#endif
    }
    
    // MARK: - Compact Layout (iOS)
#if !os(macOS)
    private var compactLayout: some View {
        VStack(spacing: 0) {
            // Inline search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notes or lesson names", text: $filters.searchText)
                if !filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { filters.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            // Content area
            Group {
                if workItems.isEmpty {
                    WorkEmptyStateView(type: .noWork)
                } else if filteredWorks.isEmpty {
                    WorkEmptyStateView(type: .noMatchingFilters)
                } else {
                    WorkContentView(
                        works: filteredWorks,
                        grouping: filters.grouping,
                        lookupService: lookupService,
                        onTapWork: handleWorkSelection,
                        onToggleComplete: handleToggleComplete
                    )
                }
            }
        }
        .popover(isPresented: $isShowingStudentFilterPopover, arrowEdge: .top) {
            StudentFilterView(
                selectedStudentIDs: $filters.selectedStudentIDs,
                students: students,
                displayName: lookupService.displayName,
                onDismiss: { isShowingStudentFilterPopover = false }
            )
        }
    }
#endif
    
    // MARK: - Regular Layout (macOS/iPad)
    private var regularLayout: some View {
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
                Group {
                    if workItems.isEmpty {
                        WorkEmptyStateView(type: .noWork)
                    } else if filteredWorks.isEmpty {
                        WorkEmptyStateView(type: .noMatchingFilters)
                    } else {
                        WorkContentView(
                            works: filteredWorks,
                            grouping: filters.grouping,
                            lookupService: lookupService,
                            onTapWork: handleWorkSelection,
                            onToggleComplete: handleToggleComplete
                        )
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
        }
    }
}
