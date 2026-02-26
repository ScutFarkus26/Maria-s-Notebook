import OSLog
import SwiftData
import SwiftUI
#if DEBUG
import Foundation
#endif

private let logger = Logger.students

private enum StudentLessonsSort: String {
    case presentThenGiven = "Default"
    case dateCreated = "Date Created"
    case dateGiven = "Date Given"
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
    @Query(sort: [SortDescriptor(\StudentLesson.id)]) private var allStudentLessons: [StudentLesson]
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
        case "dateGiven": return .dateGiven
        default: return .presentThenGiven
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
    
    /// Subject-filtered lesson IDs for filtering student lessons
    private var subjectLessonIDs: Set<UUID>? {
        guard let subject = selectedSubject else { return nil }
        let subjectLessons = lessons.filter { lesson in
            lesson.subject.caseInsensitiveCompare(subject) == .orderedSame
        }
        let ids = Set(subjectLessons.map { $0.id })
        return ids.isEmpty ? nil : ids
    }
    
    /// Filtered student lessons based on completion filter and subject selection
    /// Automatically recomputes when filter, subject, or allStudentLessons changes
    private var filteredStudentLessons: [StudentLesson] {
        // Apply completion filter
        let base: [StudentLesson]
        switch filter {
        case .all:
            // Exclude hidden undated (presented but no givenAt)
            base = allStudentLessons.filter { !($0.isGiven && $0.givenAt == nil) }
        case .completed:
            base = allStudentLessons.filter { $0.isGiven && $0.givenAt != nil }
        case .notCompleted:
            base = allStudentLessons.filter { !$0.isGiven }
        case .hiddenUndated:
            base = allStudentLessons.filter { $0.isGiven && $0.givenAt == nil }
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
    
    /// Sorted student lessons based on current sort mode
    /// Automatically recomputes when sort or filteredStudentLessons changes
    private var sortedStudentLessons: [StudentLesson] {
        #if DEBUG
        let startTime = Date()
        defer {
            let duration = Date().timeIntervalSince(startTime)
            PerformanceLogger.log(
                screenName: "StudentLessonsRootView - Sort",
                itemCount: filteredStudentLessons.count,
                duration: duration
            )
        }
        #endif
        
        switch sort {
        case .presentThenGiven:
            let upcoming = filteredStudentLessons.filter { !$0.isGiven }.sorted { lhs, rhs in
                switch (lhs.scheduledFor, rhs.scheduledFor) {
                case let (l?, r?): return l < r
                case (nil, nil): return lhs.createdAt < rhs.createdAt
                case (nil, _?): return false
                case (_?, nil): return true
                }
            }
            let given = filteredStudentLessons.filter { $0.isGiven }.sorted { lhs, rhs in
                let l = lhs.givenAt ?? .distantPast
                let r = rhs.givenAt ?? .distantPast
                return l > r
            }
            return upcoming + given
        case .dateCreated:
            return filteredStudentLessons.sorted { $0.createdAt > $1.createdAt }
        case .dateGiven:
            return filteredStudentLessons.sorted { lhs, rhs in
                switch (lhs.givenAt, rhs.givenAt) {
                case let (l?, r?): return l > r
                case (nil, nil): return lhs.createdAt > rhs.createdAt
                case (nil, _?): return false
                case (_?, nil): return true
                }
            }
        }
    }
    
    // MODERN: Specialized views for different presentation layouts
    // These are only used for .presentThenGiven sort mode
    
    /// Hidden undated presentations - automatically updates when filteredStudentLessons changes
    private var hiddenUndated: [StudentLesson] {
        filteredStudentLessons.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Upcoming presentations (not yet given) - automatically updates
    private var defaultUpcoming: [StudentLesson] {
        filteredStudentLessons.filter { !$0.isGiven }.sorted { lhs, rhs in
            switch (lhs.scheduledFor, rhs.scheduledFor) {
            case let (l?, r?): return l < r
            case (nil, nil): return lhs.createdAt < rhs.createdAt
            case (nil, _?): return false
            case (_?, nil): return true
            }
        }
    }
    
    /// Given presentations - automatically updates
    private var defaultGiven: [StudentLesson] {
        filteredStudentLessons.filter { $0.isGiven && $0.givenAt != nil }.sorted { lhs, rhs in
            let l = lhs.givenAt ?? .distantPast
            let r = rhs.givenAt ?? .distantPast
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
            if let id = selectedLessonID, let sl = filteredStudentLessons.first(where: { $0.id == id }) {
                StudentLessonDetailView(studentLesson: sl, onDone: {
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
            if let id = quickActionsLessonID, let sl = filteredStudentLessons.first(where: { $0.id == id }) {
                StudentLessonQuickActionsView(studentLesson: sl) {
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
                if let first = filteredStudentLessons.first { quickActionsLessonID = first.id }
                appRouter.clearNavigation()
            }
        }
        #if DEBUG
        .onAppear {
            PerformanceLogger.logScreenLoad(
                screenName: "StudentLessonsRootView",
                itemCounts: [
                    "studentLessons": filteredStudentLessons.count,
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
            if sort == .presentThenGiven {
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
                    let showGiven = filter != .notCompleted
                    let up = defaultUpcoming
                    let gv = defaultGiven

                    if (!showUpcoming || up.isEmpty) && (!showGiven || gv.isEmpty) {
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
                                if showGiven && !gv.isEmpty {
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
                if sortedStudentLessons.isEmpty {
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
                            ForEach(sortedStudentLessons, id: \.id) { sl in
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
