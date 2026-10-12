//
//  AppRouter.swift
//  Cosmic Daybook
//
//  Navigation coordinator for SwiftUI navigation patterns
//  Replaces NotificationCenter-based navigation with type-safe routing
//

import SwiftUI
import OSLog

/// Central navigation coordinator for the app
/// Provides type-safe navigation actions and state management
@Observable
final class AppRouter {
    private static let logger = Logger.app_
    static let shared = AppRouter()
    
    // MARK: - Navigation Actions
    
    /// Navigation destinations for sheet presentation
    enum NavigationDestination: Identifiable, Equatable {
        case newLesson(defaultArea: String?, defaultSequence: String?)
        case newStudent
        case importStudents
        case openStudentDetail(UUID)
        
        var id: String {
            switch self {
            case .newLesson: return "newLesson"
            case .newStudent: return "newStudent"
            case .importStudents: return "importStudents"
            case .openStudentDetail(let id): return "openStudentDetail_\(id.uuidString)"
            }
        }

        /// The section that answers this request, when the window has to go
        /// there first. Nil for Open Student on the Mac, which opens the child
        /// in her own window from wherever the guide is.
        var answeringSection: RootView.NavigationItem? {
            switch self {
            case .newLesson: return .lessons
            case .newStudent, .importStudents: return .students
            case .openStudentDetail:
                #if os(macOS)
                return nil
                #else
                return .students
                #endif
            }
        }
        
        static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    /// A one-shot request to open one page of one teaching album.
    struct AlbumPageRequest: Identifiable, Equatable {
        let id: UUID
        let albumID: String
        let pageIndex: Int
        let highlight: String?

        init(id: UUID = UUID(), albumID: String, pageIndex: Int, highlight: String? = nil) {
            self.id = id
            self.albumID = albumID
            self.pageIndex = pageIndex
            self.highlight = highlight
        }
    }

    /// A one-shot request to reveal one lesson's row in the Checklist grid.
    /// Carries the lesson's own area so the grid, which only ever draws one
    /// area, can switch to the right one before scrolling.
    struct ChecklistLessonRequest: Identifiable, Equatable {
        let id: UUID
        let lessonID: UUID
        let area: String

        init(id: UUID = UUID(), lessonID: UUID, area: String) {
            self.id = id
            self.lessonID = lessonID
            self.area = area
        }
    }

    /// A one-shot request for a particular lens in the shared Lessons & Work
    /// workspace. Optional focus identifiers let the destination reveal what
    /// the guide just created without opening another modal automatically.
    struct LessonsAndWorkRequest: Identifiable, Equatable {
        let id: UUID
        let scope: TriageBucket
        let presentationID: UUID?
        let workID: UUID?
        /// Which half to open when the route names no record; one that does is
        /// placed by the workspace's own partition instead.
        let preferredKind: WorkspaceKind?

        init(
            id: UUID = UUID(),
            scope: TriageBucket,
            presentationID: UUID? = nil,
            workID: UUID? = nil,
            preferredKind: WorkspaceKind? = nil
        ) {
            self.id = id
            self.scope = scope
            self.presentationID = presentationID
            self.workID = workID
            self.preferredKind = preferredKind
        }
    }
    
    // MARK: - State
    
    /// Current navigation destination to present
    var navigationDestination: NavigationDestination?
    
    /// Navigation item selection for root view (new primary navigation)
    var selectedNavItem: RootView.NavigationItem?
    
    /// One-shot destination inside the shared Lessons & Work workspace.
    var lessonsAndWorkRequest: LessonsAndWorkRequest?

    /// One-shot request to open a page of a teaching album. `AlbumsRootView`
    /// consumes it into its own `AlbumsNavModel`, which is per-surface and so
    /// can't be reached from outside the Albums section.
    var albumPageRequest: AlbumPageRequest?

    /// One-shot request to open one lesson's detail pane, consumed by
    /// `LessonsRootView`. Used by the album reader's "Notebook Lesson" jump.
    var pendingLessonID: UUID?
    
    /// Checklist deep-link filters (consumed once by ChecklistViewModel)
    var checklistFilterArea: String?
    var checklistFilterSequence: String?

    /// One-shot request to reveal a single lesson's row in the Checklist grid,
    /// consumed by `ClassAreaChecklistView`.
    var checklistLessonRequest: ChecklistLessonRequest?

    /// Refresh trigger for planning inbox
    var planningInboxRefreshTrigger: UUID = UUID()

    /// Asks RootView to present the new-work sheet; RootView resets it after
    /// consuming it. Every main window observes it, so screens inside a window
    /// use that window's `QuickCaptureActions` instead; this is left for the
    /// work agenda's New Work.
    var triggerNewWorkItem: Bool = false

    /// App lifecycle events
    var appDataWillBeReplaced: Bool = false
    var appDataDidRestore: Bool = false
    
    // MARK: - Navigation Methods
    
    /// Opens Lessons with its New Lesson sheet, for callers with no window
    /// (Siri's Create New Lesson). `LessonsRootView` answers it, on appear or
    /// while on screen. File › New Lesson… and the sidebar ask their own
    /// window instead (`WindowCreateRequests`): every window sees this one.
    func requestNewLesson(defaultArea: String? = nil, defaultSequence: String? = nil) {
        navigationDestination = .newLesson(defaultArea: defaultArea, defaultSequence: defaultSequence)
        selectedNavItem = .lessons
    }

    /// Opens Students with its Add Student sheet. Asking alone waited until
    /// Students next appeared, when the sheet popped up out of nowhere.
    func requestNewStudent() {
        navigationDestination = .newStudent
        selectedNavItem = .students
    }

    /// Opens Students with its file importer.
    func requestImportStudents() {
        navigationDestination = .importStudents
        selectedNavItem = .students
    }
    
    /// Shows Settings › Sync and backup, where backing up and restoring live
    /// (its Back Up Now says how it went). Nothing presented the old
    /// create-backup route. On the Mac the caller then opens the Settings
    /// window (`openSettings`); elsewhere Settings is a page of the app.
    func showSyncBackupSettings() {
        UserDefaults.standard.set(
            SettingsCategory.syncBackup.rawValue, forKey: UserDefaultsKeys.settingsSelectedCategory
        )
        #if !os(macOS)
        navigateTo(.settings)
        #endif
    }
    
    /// Request to show the new-work sheet. RootView owns that sheet, so this
    /// goes through the same trigger the Today `+` menu uses rather than a
    /// navigation destination nobody presents.
    func requestNewWork() {
        triggerNewWorkItem = true
    }

    /// Opens one child: in her own window on the Mac (RootView answers), and
    /// in the Students section elsewhere, which answers once it is showing.
    /// Selecting Students is what makes a tap act now rather than the next
    /// time Students happens to open.
    func requestOpenStudentDetail(_ studentID: UUID) {
        navigationDestination = .openStudentDetail(studentID)
        #if !os(macOS)
        selectedNavItem = .students
        #endif
    }

    /// Navigate to a specific navigation item
    func navigateTo(_ item: RootView.NavigationItem) {
        switch item {
        case .planningAgenda:
            navigateToLessonsAndWork(.toSchedule)
        default:
            selectedNavItem = item
        }
    }

    /// Opens the shared workspace at the point in the learning cycle requested
    /// by the caller.
    func navigateToLessonsAndWork(
        _ scope: TriageBucket = .attention,
        presentationID: UUID? = nil,
        workID: UUID? = nil,
        preferredKind: WorkspaceKind? = nil
    ) {
        lessonsAndWorkRequest = LessonsAndWorkRequest(
            scope: scope,
            presentationID: presentationID,
            workID: workID,
            preferredKind: preferredKind
        )
        selectedNavItem = .planningAgenda
    }

    func consumeLessonsAndWorkRequest() -> LessonsAndWorkRequest? {
        defer { lessonsAndWorkRequest = nil }
        return lessonsAndWorkRequest
    }

    /// Opens a finished record's history. The workspace holds only open work
    /// now — completed presentations and work live under Logs.
    func navigateToHistory(_ kind: HistoryKind) {
        UserDefaults.standard.set(kind.logsModeRaw, forKey: UserDefaultsKeys.logsMenuRootViewMode)
        selectedNavItem = .logs
    }

    enum HistoryKind {
        case presentations
        case work

        var logsModeRaw: String {
            switch self {
            case .presentations: "Presentations"
            case .work: "Works"
            }
        }
    }

    /// Kept as a source-compatible bridge for Today and older call sites.
    func navigateToPresentationFollowUps() {
        navigateToLessonsAndWork(.attention, preferredKind: .presentations)
    }

    /// Opens the Albums section at a specific page of a specific album.
    /// Used by the "Open in Album" action on a linked lesson.
    func navigateToAlbumPage(albumID: String, pageIndex: Int, highlight: String? = nil) {
        albumPageRequest = AlbumPageRequest(albumID: albumID, pageIndex: pageIndex,
                                            highlight: highlight)
        selectedNavItem = .teachingAlbums
    }

    func consumeAlbumPageRequest() -> AlbumPageRequest? {
        defer { albumPageRequest = nil }
        return albumPageRequest
    }

    /// Opens the Lessons section with one lesson's detail pane showing.
    func navigateToLesson(_ lessonID: UUID) {
        pendingLessonID = lessonID
        selectedNavItem = .lessons
    }

    func consumePendingLessonID() -> UUID? {
        defer { pendingLessonID = nil }
        return pendingLessonID
    }

    /// Navigate to checklist with optional area/sequence pre-selection
    func navigateToChecklist(area: String, sequence: String? = nil) {
        checklistFilterArea = area
        checklistFilterSequence = sequence
        selectedNavItem = .planningChecklist
    }

    /// Opens the Checklist on one lesson's row. Used by "Show in Checklist" on
    /// the presentation cards, which know the lesson but not where it sits in
    /// the grid.
    func navigateToChecklist(lessonID: UUID, area: String) {
        checklistLessonRequest = ChecklistLessonRequest(lessonID: lessonID, area: area)
        selectedNavItem = .planningChecklist
    }

    func consumeChecklistLessonRequest() -> ChecklistLessonRequest? {
        defer { checklistLessonRequest = nil }
        return checklistLessonRequest
    }

    /// Trigger planning inbox refresh
    func refreshPlanningInbox() {
        planningInboxRefreshTrigger = UUID()
    }
    
    /// What a New Lesson request carried, for the sheet's starting fields.
    struct NewLessonRequest: Equatable {
        let defaultArea: String?
        let defaultSequence: String?
    }

    /// Takes a pending New Lesson request, leaving any other screen's request
    /// in place. Reads the router's current value, so when two windows' Lessons
    /// both see the change only the first opens the sheet.
    func consumeNewLessonRequest() -> NewLessonRequest? {
        guard case .newLesson(let area, let sequence) = navigationDestination else { return nil }
        navigationDestination = nil
        return NewLessonRequest(defaultArea: area, defaultSequence: sequence)
    }

    /// The section asked for before this window existed (a reminder tapped
    /// with the app closed, Siri's Open Section on a cold launch), or else the
    /// section that answers a pending sheet request. Clears the section
    /// request, so asking for the same section again later still switches;
    /// a sheet request stays for its screen to answer.
    func takePendingNavItem() -> RootView.NavigationItem? {
        if let item = selectedNavItem {
            selectedNavItem = nil
            return item.canonical
        }
        return navigationDestination?.answeringSection
    }

    /// Clear current navigation destination
    func clearNavigation() {
        navigationDestination = nil
    }

    /// Signal that app data will be replaced
    func signalAppDataWillBeReplaced() {
        appDataWillBeReplaced = true
        // Reset after a brief moment to allow observers to react
        Task {
            do {
                try await Task.sleep(for: .seconds(UIConstants.navigationResetDelay))
            } catch {
                Self.logger.warning("Failed to sleep for navigation reset: \(error)")
            }
            self.appDataWillBeReplaced = false
        }
    }
    
    /// Signal that app data did restore
    func signalAppDataDidRestore() {
        appDataDidRestore = true
        // Reset after a brief moment to allow observers to react
        Task {
            do {
                try await Task.sleep(for: .seconds(UIConstants.navigationResetDelay))
            } catch {
                Self.logger.warning("Failed to sleep for navigation reset: \(error)")
            }
            self.appDataDidRestore = false
        }
    }
}

/// Environment key for AppRouter
struct AppRouterKey: @preconcurrency EnvironmentKey {
    static let defaultValue = AppRouter.shared
}

extension EnvironmentValues {
    var appRouter: AppRouter {
        get { self[AppRouterKey.self] }
        set { self[AppRouterKey.self] = newValue }
    }
}
