import OSLog
import SwiftUI
import CoreData
#if DEBUG
import Foundation
#endif

private let logger = Logger.students

enum PresentationsListSort: String {
    case upcomingThenPresented = "Default"
    case dateCreated = "Date Created"
    case datePresented = "Date Presented"
}

enum CompletionFilter: String {
    case all = "All"
    case completed = "Completed"
    case notCompleted = "Not Completed"
    case hiddenUndated = "Hidden"
}

struct PresentationsListView: View {
    @Environment(\.appRouter) private var appRouter
    @Environment(\.managedObjectContext) private var viewContext
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // OPTIMIZATION: Use lightweight query for change detection only
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.id, ascending: true)]) private var allLessonAssignments: FetchedResults<CDLessonAssignment>
    @FetchRequest(sortDescriptors: []) private var lessons: FetchedResults<CDLesson>
    @FetchRequest(sortDescriptors: []) private var studentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    var students: [CDStudent] {
        TestStudentsFilter.filterVisible(Array(studentsRaw).uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    @State var selectedLessonID: UUID?
    @State var quickActionsLessonID: UUID?

    // State for iPhone/Compact filter sheet
    @State private var showFilterSheet: Bool = false

    @SceneStorage("Presentations.filter") var presentationsFilterRaw: String = "all"
    @SceneStorage("Presentations.sort") private var presentationsSortRaw: String = "default"
    @SceneStorage("Presentations.subject") var presentationsSubjectRaw: String = ""
    @State var previousPresentationsFilterRaw: String?

    var filter: CompletionFilter {
        switch presentationsFilterRaw {
        case "completed": return .completed
        case "notCompleted": return .notCompleted
        case "hidden": return .hiddenUndated
        default: return .all
        }
    }

    var sort: PresentationsListSort {
        switch presentationsSortRaw {
        case "dateCreated": return .dateCreated
        case "datePresented", "dateGiven": return .datePresented
        default: return .upcomingThenPresented
        }
    }

    var selectedSubject: String? {
        StringFallbacks.valueOrNil(presentationsSubjectRaw)
    }

    private let lessonsVM = LessonsViewModel()

    var subjects: [String] {
        lessonsVM.subjects(from: Array(lessons))
    }

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    var lessonMap: [UUID: CDLesson] {
        Dictionary(lessons.compactMap { l in l.id.map { ($0, l) } }, uniquingKeysWith: { first, _ in first })
    }

    // MODERN: Computed properties with automatic dependency tracking
    // No manual cache invalidation needed - SwiftUI handles updates automatically

    /// Subject-filtered lesson IDs for filtering lesson assignments
    private var subjectLessonIDs: Set<UUID>? {
        guard let subject = selectedSubject else { return nil }
        let subjectLessons = lessons.filter { lesson in
            lesson.subject.caseInsensitiveCompare(subject) == .orderedSame
        }
        let ids = Set(subjectLessons.compactMap(\.id))
        return ids.isEmpty ? nil : ids
    }

    /// Filtered lesson assignments based on completion filter and subject selection
    /// Automatically recomputes when filter, subject, or allLessonAssignments changes
    var filteredAssignments: [CDLessonAssignment] {
        // Apply completion filter
        let base: [CDLessonAssignment]
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
    var sortedAssignments: [CDLessonAssignment] {
        #if DEBUG
        let startTime = Date()
        defer {
            let duration = Date().timeIntervalSince(startTime)
            PerformanceLogger.log(
                screenName: "PresentationsListView - Sort",
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
                case (nil, nil): return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
                case (nil, _?): return false
                case (_?, nil): return true
                }
            }
            let presented = filteredAssignments.filter(\.isPresented).sorted { lhs, rhs in
                let l = lhs.presentedAt ?? .distantPast
                let r = rhs.presentedAt ?? .distantPast
                return l > r
            }
            return upcoming + presented
        case .dateCreated:
            return filteredAssignments.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .datePresented:
            return filteredAssignments.sorted { lhs, rhs in
                switch (lhs.presentedAt, rhs.presentedAt) {
                case let (l?, r?): return l > r
                case (nil, nil): return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
                case (nil, _?): return false
                case (_?, nil): return true
                }
            }
        }
    }

    // MODERN: Specialized views for different presentation layouts
    // These are only used for .upcomingThenPresented sort mode

    /// Hidden undated presentations - automatically updates when filteredAssignments changes
    var hiddenUndated: [CDLessonAssignment] {
        filteredAssignments.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// Upcoming presentations (not yet presented) - automatically updates
    var defaultUpcoming: [CDLessonAssignment] {
        filteredAssignments.filter { !$0.isPresented }.sorted { lhs, rhs in
            switch (lhs.scheduledFor, rhs.scheduledFor) {
            case let (l?, r?): return l < r
            case (nil, nil): return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
            case (nil, _?): return false
            case (_?, nil): return true
            }
        }
    }

    /// Presented assignments - automatically updates
    var defaultPresented: [CDLessonAssignment] {
        filteredAssignments.filter { $0.isPresented && $0.presentedAt != nil }.sorted { lhs, rhs in
            let l = lhs.presentedAt ?? .distantPast
            let r = rhs.presentedAt ?? .distantPast
            return l > r
        }
    }

    var columns: [GridItem] {
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
                PresentationDetailView(lessonAssignment: sl, onDone: {
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
        .sheet(isPresented: Binding(
            get: { quickActionsLessonID != nil },
            set: { if !$0 { quickActionsLessonID = nil } }
        )) {
            if let id = quickActionsLessonID, let sl = filteredAssignments.first(where: { $0.id == id }) {
                PresentationQuickActionsView(lessonAssignment: sl) {
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
                screenName: "PresentationsListView",
                itemCounts: [
                    "lessonAssignments": filteredAssignments.count,
                    "lessons": lessons.count,
                    "students": students.count
                ]
            )
        }
        #endif
    }
}

#Preview {
    PresentationsListView()
}
