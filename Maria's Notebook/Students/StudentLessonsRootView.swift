import OSLog
import SwiftData
import SwiftUI
#if DEBUG
import Foundation
#endif

private let logger = Logger.students

private enum StudentLessonsSort: String {
    case upcomingThenPresented = "Default"
    case dateCreated = "Date Created"
    case datePresented = "Date Presented"
}

private enum CompletionFilter: String {
    case all = "All"
    case completed = "Completed"
    case notCompleted = "Not Completed"
    case hiddenUndated = "Hidden"
}

struct StudentLessonsRootView: View {
    @Environment(\.appRouter) private var appRouter
    @Environment(\.modelContext) private var modelContext
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // OPTIMIZATION: Use lightweight query for change detection only
    @Query(sort: [SortDescriptor(\LessonAssignment.id)]) private var allLessonAssignments: [LessonAssignment]
    @Query private var lessons: [Lesson]
    @Query private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    @State private var selectedLessonID: UUID?
    @State private var quickActionsLessonID: UUID?
    
    // State for iPhone/Compact filter sheet
    @State private var showFilterSheet: Bool = false

    @SceneStorage("StudentLessons.filter") private var studentLessonsFilterRaw: String = "all"
    @SceneStorage("StudentLessons.sort") private var studentLessonsSortRaw: String = "default"
    @SceneStorage("StudentLessons.subject") private var studentLessonsSubjectRaw: String = ""
    @State private var previousStudentLessonsFilterRaw: String?

    private var filter: CompletionFilter {
        switch studentLessonsFilterRaw {
        case "completed": return .completed
        case "notCompleted": return .notCompleted
        case "hidden": return .hiddenUndated
        default: return .all
        }
    }

    private var sort: StudentLessonsSort {
        switch studentLessonsSortRaw {
        case "dateCreated": return .dateCreated
        case "datePresented", "dateGiven": return .datePresented
        default: return .upcomingThenPresented
        }
    }

    private var selectedSubject: String? {
        StringFallbacks.valueOrNil(studentLessonsSubjectRaw)
    }

    private let lessonsVM = LessonsViewModel()

    private var subjects: [String] {
        lessonsVM.subjects(from: lessons)
    }

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonMap: [UUID: Lesson] {
        Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    
    // MODERN: Computed properties with automatic dependency tracking
    // No manual cache invalidation needed - SwiftUI handles updates automatically
    
    /// Subject-filtered lesson IDs for filtering lesson assignments
    private var subjectLessonIDs: Set<UUID>? {
        guard let subject = selectedSubject else { return nil }
        let subjectLessons = lessons.filter { lesson in
            lesson.subject.caseInsensitiveCompare(subject) == .orderedSame
        }
        let ids = Set(subjectLessons.map { $0.id })
        return ids.isEmpty ? nil : ids
    }
    
    /// Filtered lesson assignments based on completion filter and subject selection
    /// Automatically recomputes when filter, subject, or allLessonAssignments changes
    private var filteredAssignments: [LessonAssignment] {
        // Apply completion filter
        let base: [LessonAssignment]
        switch filter {
        case .all:
            // Exclude hidden undated (presented but no presentedAt)
            base = allLessonAssignments.filter { !($0.isPresented && $0.presentedAt == nil) }
        case .completed:
            base = allLessonAssignments.filter { $0.isPresented && $0.presentedAt != nil }
        case .notCompleted:
            base = allLessonAssignments.filter { !$0.isPresented }
        case .hiddenUndated:
            base = allLessonAssignments.filter { $0.isPresented && $0.presentedAt == nil }
        }
        
        // Apply subject filter if selected
        if let lessonIDs = subjectLessonIDs {
            return base.filter { sl in
                guard let lessonID = UUID(uuidString: sl.lessonID) else { return false }
                return lessonIDs.contains(lessonID)
            }
        }
        
        return base
    }
    
    /// Sorted lesson assignments based on current sort mode
    /// Automatically recomputes when sort or filteredAssignments changes
    private var sortedAssignments: [LessonAssignment] {
        #if DEBUG
        let startTime = Date()
        defer {
            let duration = Date().timeIntervalSince(startTime)
            PerformanceLogger.log(
                screenName: "StudentLessonsRootView - Sort",
                itemCount: filteredAssignments.count,
                duration: duration
            )
        }
        #endif
        
        switch sort {
        case .upcomingThenPresented:
            let upcoming = filteredAssignments.filter { !$0.isPresented }.sorted { lhs, rhs in
                switch (lhs.scheduledFor, rhs.scheduledFor) {
                case let (l?, r?): return l < r
                case (nil, nil): return lhs.createdAt < rhs.createdAt
                case (nil, _?): return false
                case (_?, nil): return true
                }
            }
            let presented = filteredAssignments.filter { $0.isPresented }.sorted { lhs, rhs in
                let l = lhs.presentedAt ?? .distantPast
                let r = rhs.presentedAt ?? .distantPast
                return l > r
            }
            return upcoming + presented
        case .dateCreated:
            return filteredAssignments.sorted { $0.createdAt > $1.createdAt }
        case .datePresented:
            return filteredAssignments.sorted { lhs, rhs in
                switch (lhs.presentedAt, rhs.presentedAt) {
                case let (l?, r?): return l > r
                case (nil, nil): return lhs.createdAt > rhs.createdAt
                case (nil, _?): return false
                case (_?, nil): return true
                }
            }
        }
    }
    
    // MODERN: Specialized views for different presentation layouts
    // These are only used for .upcomingThenPresented sort mode
    
    /// Hidden undated presentations - automatically updates when filteredAssignments changes
    private var hiddenUndated: [LessonAssignment] {
        filteredAssignments.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Upcoming presentations (not yet presented) - automatically updates
    private var defaultUpcoming: [LessonAssignment] {
        filteredAssignments.filter { !$0.isPresented }.sorted { lhs, rhs in
            switch (lhs.scheduledFor, rhs.scheduledFor) {
            case let (l?, r?): return l < r
            case (nil, nil): return lhs.createdAt < rhs.createdAt
            case (nil, _?): return false
            case (_?, nil): return true
            }
        }
    }
    
    /// Presented assignments - automatically updates
    private var defaultPresented: [LessonAssignment] {
        filteredAssignments.filter { $0.isPresented && $0.presentedAt != nil }.sorted { lhs, rhs in
            let l = lhs.presentedAt ?? .distantPast
            let r = rhs.presentedAt ?? .distantPast
            return l > r
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 24)]
    }

    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                // iPhone/Compact: Content only, filters in sheet
                content
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Filters", systemImage: "line.3.horizontal.decrease.circle") {
                                showFilterSheet = true
                            }
                        }
                    }
                    .sheet(isPresented: $showFilterSheet) {
                        NavigationStack {
                            sidebar
                                .navigationTitle("Filters")
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Done") { showFilterSheet = false }
                                    }
                                }
                        }
                        .presentationDetents([.medium, .large])
                    }
            } else {
                // iPad/Regular: Sidebar + Content
                HStack(spacing: 0) {
                    sidebar
                    Divider()
                    content
                }
            }
            #else
            // macOS: Sidebar + Content
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
            }
            #endif
        }
        .sheet(isPresented: Binding(get: { selectedLessonID != nil }, set: { if !$0 { selectedLessonID = nil } })) {
            if let id = selectedLessonID, let sl = filteredAssignments.first(where: { $0.id == id }) {
                StudentLessonDetailView(lessonAssignment: sl, onDone: {
                    selectedLessonID = nil
                })
            } else {
                // Keep the sheet alive instead of returning EmptyView to avoid ViewBridge cancellation
                ProgressView("Loading…")
                    .frame(minWidth: 320, minHeight: 240)
                    .task {
                        // Dismiss if the item is no longer available after a brief delay
                        do {
                            try await Task.sleep(for: .milliseconds(100)) // 0.1 seconds
                        } catch {
                            logger.warning("selectedLessonID sheet task sleep interrupted: \(error)")
                        }
                        if selectedLessonID != nil {
                            selectedLessonID = nil
                        }
                    }
            }
        }
        .sheet(isPresented: Binding(get: { quickActionsLessonID != nil }, set: { if !$0 { quickActionsLessonID = nil } })) {
            if let id = quickActionsLessonID, let sl = filteredAssignments.first(where: { $0.id == id }) {
                StudentLessonQuickActionsView(lessonAssignment: sl) {
                    quickActionsLessonID = nil
                }
            } else {
                // Keep the sheet alive instead of returning EmptyView to avoid ViewBridge cancellation
                ProgressView("Loading…")
                    .frame(minWidth: 320, minHeight: 240)
                    .task {
                        // Dismiss if the item is no longer available after a brief delay
                        do {
                            try await Task.sleep(for: .milliseconds(100)) // 0.1 seconds
                        } catch {
                            logger.warning("quickActionsLessonID sheet task sleep interrupted: \(error)")
                        }
                        if quickActionsLessonID != nil {
                            quickActionsLessonID = nil
                        }
                    }
            }
        }
        .onChange(of: appRouter.navigationDestination) { _, destination in
            if case .quickActions = destination {
                if let first = filteredAssignments.first { quickActionsLessonID = first.id }
                appRouter.clearNavigation()
            }
        }
        #if DEBUG
        .onAppear {
            PerformanceLogger.logScreenLoad(
                screenName: "StudentLessonsRootView",
                itemCounts: [
                    "lessonAssignments": filteredAssignments.count,
                    "lessons": lessons.count,
                    "students": students.count
                ]
            )
        }
        #endif
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filters")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                SidebarFilterButton(
                    icon: "line.3.horizontal.decrease.circle",
                    title: CompletionFilter.all.rawValue,
                    color: .accentColor,
                    isSelected: filter == .all
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        studentLessonsFilterRaw = "all"
                    }
                }

                SidebarFilterButton(
                    icon: "checkmark.circle.fill",
                    title: CompletionFilter.completed.rawValue,
                    color: .green,
                    isSelected: filter == .completed
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        studentLessonsFilterRaw = "completed"
                    }
                }

                SidebarFilterButton(
                    icon: "circle.dashed",
                    title: CompletionFilter.notCompleted.rawValue,
                    color: .orange,
                    isSelected: filter == .notCompleted
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        studentLessonsFilterRaw = "notCompleted"
                    }
                }

                Text("Subject")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                // Clear subject filter
                SidebarFilterButton(
                    icon: "rectangle.3.group",
                    title: "All Subjects",
                    color: .accentColor,
                    isSelected: selectedSubject == nil
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        studentLessonsSubjectRaw = ""
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
                            studentLessonsSubjectRaw = subject
                        }
                    }
                }

                Divider()

                SidebarFilterButton(
                    icon: "eye.slash.fill",
                    title: CompletionFilter.hiddenUndated.rawValue,
                    color: .gray,
                    isSelected: filter == .hiddenUndated
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        if filter == .hiddenUndated {
                            studentLessonsFilterRaw = previousStudentLessonsFilterRaw ?? "all"
                        } else {
                            previousStudentLessonsFilterRaw = studentLessonsFilterRaw
                            studentLessonsFilterRaw = "hidden"
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .padding(.leading, 16)
        }
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .topLeading) // FIX: Allow flexible width in sheet
        #if os(macOS)
        .frame(width: 200)
        #endif
        .background(Color.gray.opacity(0.08))
    }

    // MARK: - Content (Unchanged)
    private var content: some View {
        Group {
            if sort == .upcomingThenPresented {
                if filter == .hiddenUndated {
                    if hiddenUndated.isEmpty {
                        VStack(spacing: 8) {
                            Text("No hidden presentations")
                                .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                            Text("Presentations marked presented without a date will appear here.")
                                .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Image(systemName: "eye.slash.fill")
                                        .foregroundStyle(.secondary)
                                    Text("Hidden")
                                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                    ForEach(hiddenUndated, id: \.id) { sl in
                                        StudentLessonCard(snapshot: sl.snapshot(), lesson: UUID(uuidString: sl.lessonID).flatMap { lessonMap[$0] }, students: students)
                                            .onTapGesture { selectedLessonID = sl.id }
                                            .contextMenu {
                                                Button {
                                                    quickActionsLessonID = sl.id
                                                } label: {
                                                    Label("Quick Actions…", systemImage: "bolt")
                                                }
                                            }
                                    }
                                }
                            }
                            .padding(24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    let showUpcoming = filter != .completed
                    let showPresented = filter != .notCompleted
                    let up = defaultUpcoming
                    let gv = defaultPresented

                    if (!showUpcoming || up.isEmpty) && (!showPresented || gv.isEmpty) {
                        VStack(spacing: 8) {
                            Text("No presentations")
                                .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                            Text("Try adjusting your filters or add presentations from the Lessons library.")
                                .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                if showUpcoming && !up.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 10) {
                                            Image(systemName: "clock")
                                                .foregroundStyle(.secondary)
                                            Text("To Present")
                                                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                            ForEach(up, id: \.id) { sl in
                                                StudentLessonCard(snapshot: sl.snapshot(), lesson: UUID(uuidString: sl.lessonID).flatMap { lessonMap[$0] }, students: students)
                                                    .onTapGesture { selectedLessonID = sl.id }
                                                    .contextMenu {
                                                        Button {
                                                            quickActionsLessonID = sl.id
                                                        } label: {
                                                            Label("Quick Actions…", systemImage: "bolt")
                                                        }
                                                    }
                                            }
                                        }
                                    }
                                }
                                if showPresented && !gv.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 10) {
                                            Image(systemName: "checkmark.circle")
                                                .foregroundStyle(.secondary)
                                            Text("Given")
                                                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                            ForEach(gv, id: \.id) { sl in
                                                StudentLessonCard(snapshot: sl.snapshot(), lesson: UUID(uuidString: sl.lessonID).flatMap { lessonMap[$0] }, students: students)
                                                    .onTapGesture { selectedLessonID = sl.id }
                                                    .contextMenu {
                                                        Button {
                                                            quickActionsLessonID = sl.id
                                                        } label: {
                                                            Label("Quick Actions…", systemImage: "bolt")
                                                        }
                                                    }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                if sortedAssignments.isEmpty {
                    VStack(spacing: 8) {
                        Text("No presentations")
                            .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                        Text("Try adjusting your filters or add presentations from the Lessons library.")
                            .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(sortedAssignments, id: \.id) { sl in
                                StudentLessonCard(snapshot: sl.snapshot(), lesson: UUID(uuidString: sl.lessonID).flatMap { lessonMap[$0] }, students: students)
                                    .onTapGesture { selectedLessonID = sl.id }
                                    .contextMenu {
                                        Button {
                                            quickActionsLessonID = sl.id
                                        } label: {
                                            Label("Quick Actions…", systemImage: "bolt")
                                        }
                                    }
                            }
                        }
                        .padding(24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}


#Preview {
    StudentLessonsRootView()
}
