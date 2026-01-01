import SwiftUI
import SwiftData
#if DEBUG
import Foundation
#endif

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
    @Query private var studentLessons: [StudentLesson]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]

    @State private var selectedLessonID: UUID? = nil
    @State private var quickActionsLessonID: UUID? = nil

    @SceneStorage("StudentLessons.filter") private var studentLessonsFilterRaw: String = "all"
    @SceneStorage("StudentLessons.sort") private var studentLessonsSortRaw: String = "default"
    @SceneStorage("StudentLessons.subject") private var studentLessonsSubjectRaw: String = ""
    @State private var previousStudentLessonsFilterRaw: String? = nil

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
        studentLessonsSubjectRaw.isEmpty ? nil : studentLessonsSubjectRaw
    }

    private let lessonsVM = LessonsViewModel()

    private var subjects: [String] {
        lessonsVM.subjects(from: lessons)
    }

    private var lessonMap: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }

    private func applySubjectFilter(_ base: [StudentLesson]) -> [StudentLesson] {
        if let subject = selectedSubject {
            return base.filter { sl in
                // CloudKit compatibility: Convert String lessonID to UUID for lookup
                if let lessonIDUUID = UUID(uuidString: sl.lessonID),
                   let l = lessonMap[lessonIDUUID] {
                    return l.subject.caseInsensitiveCompare(subject) == .orderedSame
                }
                return false
            }
        }
        return base
    }

    private var hiddenUndated: [StudentLesson] {
        var base = studentLessons.filter { $0.isGiven && $0.givenAt == nil }
        base = applySubjectFilter(base)
        // Most recent created first for visibility
        return base.sorted { $0.createdAt > $1.createdAt }
    }

    private var defaultUpcoming: [StudentLesson] {
        var base = studentLessons.filter { !$0.isGiven }
        base = applySubjectFilter(base)
        return base.sorted { lhs, rhs in
            switch (lhs.scheduledFor, rhs.scheduledFor) {
            case let (l?, r?):
                return l < r
            case (nil, nil):
                return lhs.createdAt < rhs.createdAt
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }

    private var defaultGiven: [StudentLesson] {
        var base = studentLessons.filter { $0.isGiven && $0.givenAt != nil }
        base = applySubjectFilter(base)
        return base.sorted { lhs, rhs in
            let l = lhs.givenAt ?? .distantPast
            let r = rhs.givenAt ?? .distantPast
            return l > r
        }
    }

    private var filteredAndSorted: [StudentLesson] {
        #if DEBUG
        let startTime = Date()
        #endif
        
        // Apply completion filter first
        var base: [StudentLesson]
        switch filter {
        case .all:
            base = studentLessons
        case .completed:
            base = studentLessons.filter { $0.isGiven && $0.givenAt != nil }
        case .notCompleted:
            base = studentLessons.filter { !$0.isGiven }
        case .hiddenUndated:
            base = studentLessons.filter { $0.isGiven && $0.givenAt == nil }
        }

        if filter != .hiddenUndated {
            base = base.filter { !($0.isGiven && $0.givenAt == nil) }
        }

        // Subject filter (using referenced Lesson)
        if let subject = selectedSubject {
            base = base.filter { sl in
                // CloudKit compatibility: Convert String lessonID to UUID for lookup
                if let lessonIDUUID = UUID(uuidString: sl.lessonID),
                   let l = lessonMap[lessonIDUUID] {
                    return l.subject.caseInsensitiveCompare(subject) == .orderedSame
                }
                return false
            }
        }

        // Sorting
        let result: [StudentLesson]
        switch sort {
        case .presentThenGiven:
            let upcoming: [StudentLesson] = base.filter { !$0.isGiven }.sorted { lhs, rhs in
                switch (lhs.scheduledFor, rhs.scheduledFor) {
                case let (l?, r?):
                    return l < r
                case (nil, nil):
                    return lhs.createdAt < rhs.createdAt
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                }
            }
            let given: [StudentLesson] = base.filter { $0.isGiven }.sorted { lhs, rhs in
                let l = lhs.givenAt ?? .distantPast
                let r = rhs.givenAt ?? .distantPast
                return l > r
            }
            result = upcoming + given
        case .dateCreated:
            result = base.sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
        case .dateGiven:
            result = base.sorted { lhs, rhs in
                switch (lhs.givenAt, rhs.givenAt) {
                case let (l?, r?):
                    return l > r
                case (nil, nil):
                    // If neither has a givenAt, fall back to createdAt
                    return lhs.createdAt > rhs.createdAt
                case (nil, _?):
                    // Place undated (not yet given) after those with dates
                    return false
                case (_?, nil):
                    return true
                }
            }
        }
        
        #if DEBUG
        let duration = Date().timeIntervalSince(startTime)
        PerformanceLogger.log(
            screenName: "StudentLessonsRootView - Filter & Sort",
            itemCount: result.count,
            duration: duration
        )
        #endif
        
        return result
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 24)]
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .sheet(isPresented: Binding(get: { selectedLessonID != nil }, set: { if !$0 { selectedLessonID = nil } })) {
            if let id = selectedLessonID, let sl = studentLessons.first(where: { $0.id == id }) {
                StudentLessonDetailView(studentLesson: sl, onDone: {
                    selectedLessonID = nil
                })
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: Binding(get: { quickActionsLessonID != nil }, set: { if !$0 { quickActionsLessonID = nil } })) {
            if let id = quickActionsLessonID, let sl = studentLessons.first(where: { $0.id == id }) {
                StudentLessonQuickActionsView(studentLesson: sl) {
                    quickActionsLessonID = nil
                }
            } else {
                EmptyView()
            }
        }
        .onChange(of: appRouter.navigationDestination) { _, destination in
            if case .quickActions = destination {
                // If there is at least one student lesson, open quick actions for the first upcoming
                if let first = studentLessons.first { quickActionsLessonID = first.id }
                appRouter.clearNavigation()
            }
        }
        .onAppear {
            #if DEBUG
            PerformanceLogger.logScreenLoad(
                screenName: "StudentLessonsRootView",
                itemCounts: [
                    "studentLessons": studentLessons.count,
                    "lessons": lessons.count,
                    "students": students.count
                ]
            )
            #endif
        }
        .onChange(of: studentLessons.count) { _, newCount in
            #if DEBUG
            PerformanceLogger.log(
                screenName: "StudentLessonsRootView - Query Update",
                itemCount: newCount,
                duration: 0
            )
            #endif
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
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
                        // Tapping Hidden again: restore the previous filter (default to All)
                        studentLessonsFilterRaw = previousStudentLessonsFilterRaw ?? "all"
                    } else {
                        // Entering Hidden: remember the current filter to allow toggling back
                        previousStudentLessonsFilterRaw = studentLessonsFilterRaw
                        studentLessonsFilterRaw = "hidden"
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

    // MARK: - Content
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
                if filteredAndSorted.isEmpty {
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
                            ForEach(filteredAndSorted, id: \.id) { sl in
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
