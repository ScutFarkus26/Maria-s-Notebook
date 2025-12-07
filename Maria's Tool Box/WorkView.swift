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
    @SceneStorage("WorkView.grouping") private var groupingStorage: String = ""
    @SceneStorage("WorkView.mode") private var modeStorage: String = "overview"
    @SceneStorage("WorkView.level") private var levelStorage: String = "All"
    
    private enum Mode: String { case overview, items }
    @State private var mode: Mode = .overview
    
    // Lookup service
    private var lookupService: WorkLookupService {
        WorkLookupService(
            students: students,
            lessons: lessons,
            studentLessons: studentLessons
        )
    }
    
    private var filteredWorks: [WorkModel] {
        let base = filters.filterWorks(
            workItems,
            studentLessonsByID: lookupService.studentLessonsByID,
            lessonsByID: lookupService.lessonsByID
        )
        switch filters.level {
        case .all:
            return base
        case .lower, .upper:
            let map = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
            return base.filter { work in
                if work.participants.isEmpty {
                    // Fallback: no participants yet — use studentIDs
                    return work.studentIDs.contains { id in
                        guard let s = map[id] else { return false }
                        return (filters.level == .lower && s.level == .lower) || (filters.level == .upper && s.level == .upper)
                    }
                } else {
                    return work.participants.contains { p in
                        guard let s = map[p.studentID] else { return false }
                        return (filters.level == .lower && s.level == .lower) || (filters.level == .upper && s.level == .upper)
                    }
                }
            }
        }
    }
    
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

    private func isStudentVisible(_ s: Student) -> Bool {
        let matchesLevel: Bool = {
            switch filters.level {
            case .all: return true
            case .lower: return s.level == .lower
            case .upper: return s.level == .upper
            }
        }()
        let matchesSelection = filters.selectedStudentIDs.isEmpty || filters.selectedStudentIDs.contains(s.id)
        return matchesLevel && matchesSelection
    }

    private func isParticipantVisible(_ studentID: UUID) -> Bool {
        if !filters.selectedStudentIDs.isEmpty && !filters.selectedStudentIDs.contains(studentID) { return false }
        switch filters.level {
        case .all: return true
        case .lower: return studentsByID[studentID]?.level == .lower
        case .upper: return studentsByID[studentID]?.level == .upper
        }
    }

    private var openWorks: [WorkModel] { filteredWorks.filter { $0.isOpen } }

    private var openWorksByStudentID: [UUID: [WorkModel]] {
        var map: [UUID: [WorkModel]] = [:]
        for work in openWorks {
            if work.participants.isEmpty {
                // Fallback: if no participants, treat all listed studentIDs as open
                for sid in work.studentIDs {
                    guard isParticipantVisible(sid) else { continue }
                    map[sid, default: []].append(work)
                }
            } else {
                // Normal path: include only participants who haven't completed yet
                for p in work.participants {
                    guard isParticipantVisible(p.studentID) else { continue }
                    if p.completedAt == nil {
                        map[p.studentID, default: []].append(work)
                    }
                }
            }
        }
        return map
    }
    
    private var workSummaries: [StudentWorkSummary] {
        var counts: [UUID: (practice: Int, follow: Int, research: Int)] = [:]
        for work in openWorks {
            if work.participants.isEmpty {
                // Fallback: if no participants, treat all listed studentIDs as open
                for sid in work.studentIDs {
                    guard isParticipantVisible(sid) else { continue }
                    switch work.workType {
                    case .practice:
                        counts[sid, default: (0,0,0)].practice += 1
                    case .followUp:
                        counts[sid, default: (0,0,0)].follow += 1
                    case .research:
                        counts[sid, default: (0,0,0)].research += 1
                    }
                }
            } else {
                // Normal path: count only participants who haven't completed yet
                for p in work.participants {
                    guard isParticipantVisible(p.studentID) else { continue }
                    switch work.workType {
                    case .practice:
                        if p.completedAt == nil { counts[p.studentID, default: (0,0,0)].practice += 1 }
                    case .followUp:
                        if p.completedAt == nil { counts[p.studentID, default: (0,0,0)].follow += 1 }
                    case .research:
                        if p.completedAt == nil { counts[p.studentID, default: (0,0,0)].research += 1 }
                    }
                }
            }
        }
        let visible = students.filter { isStudentVisible($0) }
        return visible.map { s in
            let c = counts[s.id, default: (0,0,0)]
            return StudentWorkSummary(id: s.id, student: s, practiceOpen: c.practice, followUpOpen: c.follow, researchOpen: c.research)
        }
        .sorted { lhs, rhs in
            if lhs.totalOpen == rhs.totalOpen {
                return lhs.student.fullName.localizedCaseInsensitiveCompare(rhs.student.fullName) == .orderedAscending
            }
            return lhs.totalOpen > rhs.totalOpen
        }
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
        
        if let level = WorkFilters.LevelFilter(rawValue: levelStorage) {
            filters.level = level
        }
        mode = Mode(rawValue: modeStorage) ?? .overview
    }
    
    private func syncFiltersToStorage() {
        groupingStorage = filters.grouping.rawValue
        selectedSubjectStorage = filters.selectedSubject ?? ""
        searchTextStorage = filters.searchText
        selectedStudentIDsStorage = filters.selectedStudentIDs.map { $0.uuidString }.joined(separator: ",")
        levelStorage = filters.level.rawValue
        modeStorage = mode.rawValue
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
            Section("Level") {
                Button("All") { filters.level = .all }
                Button("Lower") { filters.level = .lower }
                Button("Upper") { filters.level = .upper }
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
                mode = Mode(rawValue: modeStorage) ?? .overview
            }
            .onChange(of: filters.grouping) { _, _ in syncFiltersToStorage() }
            .onChange(of: filters.selectedSubject) { _, _ in syncFiltersToStorage() }
            .onChange(of: filters.searchText) { _, _ in syncFiltersToStorage() }
            .onChange(of: filters.selectedStudentIDs) { _, _ in syncFiltersToStorage() }
            .onChange(of: filters.level) { _, _ in syncFiltersToStorage() }
            .onChange(of: mode) { _, _ in syncFiltersToStorage() }
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
                ToolbarItem(placement: .topBarLeading) {
                    Picker("", selection: $mode) {
                        Text("Overview").tag(Mode.overview)
                        Text("Items").tag(Mode.items)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
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
                if mode == .overview {
                    WorkOverviewList(
                        summaries: workSummaries,
                        openWorksByStudentID: openWorksByStudentID,
                        lookupService: lookupService,
                        onTapStudent: { student in
                            filters.selectedStudentIDs = [student.id]
                            mode = .items
                        },
                        onTapWork: handleWorkSelection
                    )
                } else {
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
#if os(macOS)
                Picker("Mode", selection: $mode) {
                    Text("Overview").tag(Mode.overview)
                    Text("Items").tag(Mode.items)
                }
                .pickerStyle(.segmented)
                .padding([.top, .horizontal])
#endif
                Group {
                    if mode == .overview {
                        WorkOverviewList(
                            summaries: workSummaries,
                            openWorksByStudentID: openWorksByStudentID,
                            lookupService: lookupService,
                            onTapStudent: { student in
                                filters.selectedStudentIDs = [student.id]
                                mode = .items
                            },
                            onTapWork: handleWorkSelection
                        )
                    } else {
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

