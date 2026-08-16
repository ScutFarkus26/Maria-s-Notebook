//
//  AppRouter.swift
//  Maria's Notebook
//
//  Navigation coordinator for SwiftUI navigation patterns
//  Replaces NotificationCenter-based navigation with type-safe routing
//

import SwiftUI
import OSLog

/// Central navigation coordinator for the app
/// Provides type-safe navigation actions and state management
@Observable
@MainActor
final class AppRouter {
    private static let logger = Logger.app_
    static let shared = AppRouter()
    
    // MARK: - Navigation Actions
    
    /// Navigation destinations for sheet presentation
    enum NavigationDestination: Identifiable, Equatable {
        case newLesson(defaultArea: String?, defaultSequence: String?)
        case importLessons
        case newStudent
        case importStudents
        case createBackup
        case restoreBackup
        case newWork
        case openAttendance
        case openStudentDetail(UUID)
        case backfillIsPresented
        case quickActions
        
        var id: String {
            switch self {
            case .newLesson: return "newLesson"
            case .importLessons: return "importLessons"
            case .newStudent: return "newStudent"
            case .importStudents: return "importStudents"
            case .createBackup: return "createBackup"
            case .restoreBackup: return "restoreBackup"
            case .newWork: return "newWork"
            case .openAttendance: return "openAttendance"
            case .openStudentDetail(let id): return "openStudentDetail_\(id.uuidString)"
            case .backfillIsPresented: return "backfillIsPresented"
            case .quickActions: return "quickActions"
            }
        }
        
        static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    /// Planning lesson for student on date
    struct PlanLessonRequest: Equatable {
        let studentID: UUID
        let date: Date
        
        static func == (lhs: PlanLessonRequest, rhs: PlanLessonRequest) -> Bool {
            lhs.studentID == rhs.studentID && lhs.date == rhs.date
        }
    }

    /// A one-shot request for a particular lens in the shared Lessons & Work
    /// workspace. Optional focus identifiers let the destination reveal what
    /// the guide just created without opening another modal automatically.
    struct LessonsAndWorkRequest: Identifiable, Equatable {
        let id: UUID
        let scope: LessonsAndWorkScope
        let presentationID: UUID?
        let workID: UUID?

        init(
            id: UUID = UUID(),
            scope: LessonsAndWorkScope,
            presentationID: UUID? = nil,
            workID: UUID? = nil
        ) {
            self.id = id
            self.scope = scope
            self.presentationID = presentationID
            self.workID = workID
        }
    }
    
    // MARK: - State
    
    /// Current navigation destination to present
    var navigationDestination: NavigationDestination?
    
    /// Plan lesson request
    var planLessonRequest: PlanLessonRequest?
    
    /// Navigation item selection for root view (new primary navigation)
    var selectedNavItem: RootView.NavigationItem?
    
    /// Students mode selection
    var studentsMode: String?

    /// One-shot destination inside the shared Lessons & Work workspace.
    var lessonsAndWorkRequest: LessonsAndWorkRequest?
    
    /// Checklist deep-link filters (consumed once by ChecklistViewModel)
    var checklistFilterArea: String?
    var checklistFilterSequence: String?

    /// Refresh trigger for planning inbox
    var planningInboxRefreshTrigger: UUID = UUID()

    /// A companion-suggested question waiting for Ask AI to consume it.
    /// The prompt is set only after the guide explicitly chooses an action.
    var pendingAIQuestion: String?

    /// App-wide progress state so the companion can show that Ask AI is working
    /// even if the guide navigates to another surface.
    var isAIWorking: Bool = false

    /// Triggers for quick-action sheets shown by RootView. Setting any to true asks
    /// RootView to present the corresponding sheet; RootView resets the value to false
    /// after consuming it. Used by Today's toolbar `+` menu and other entry points
    /// that don't have direct access to RootView's local sheet state.
    var triggerNewWorkItem: Bool = false
    var triggerRecordPractice: Bool = false
    var triggerNewPresentation: Bool = false
    var triggerCommandBar: Bool = false

    /// App lifecycle events
    var appDataWillBeReplaced: Bool = false
    var appDataDidRestore: Bool = false
    
    // MARK: - Navigation Methods
    
    /// Request to show new lesson sheet
    func requestNewLesson(defaultArea: String? = nil, defaultSequence: String? = nil) {
        navigationDestination = .newLesson(defaultArea: defaultArea, defaultSequence: defaultSequence)
    }
    
    /// Request to show import lessons
    func requestImportLessons() {
        navigationDestination = .importLessons
    }
    
    /// Request to show new student sheet
    func requestNewStudent() {
        navigationDestination = .newStudent
    }
    
    /// Request to show import students
    func requestImportStudents() {
        navigationDestination = .importStudents
    }
    
    /// Request to create backup
    func requestCreateBackup() {
        navigationDestination = .createBackup
    }
    
    /// Request to restore backup
    func requestRestoreBackup() {
        navigationDestination = .restoreBackup
    }
    
    /// Request to show new work
    func requestNewWork() {
        navigationDestination = .newWork
    }

    /// Request to open student detail
    func requestOpenStudentDetail(_ studentID: UUID) {
        navigationDestination = .openStudentDetail(studentID)
    }
    
    /// Request to show backfill
    func requestBackfillIsPresented() {
        navigationDestination = .backfillIsPresented
    }

    /// Request to plan lesson for student on date
    func requestPlanLessonForStudentOnDate(studentID: UUID, date: Date) {
        planLessonRequest = PlanLessonRequest(studentID: studentID, date: date)
    }
    
    /// Navigate to a specific navigation item
    func navigateTo(_ item: RootView.NavigationItem) {
        switch item {
        case .planningAgenda:
            navigateToLessonsAndWork(.upcoming)
        case .planningWork:
            navigateToLessonsAndWork(.childrenWorking)
        default:
            selectedNavItem = item
        }
    }

    /// Opens the shared workspace at the point in the learning cycle requested
    /// by the caller. Both former planning destinations now route here.
    func navigateToLessonsAndWork(
        _ scope: LessonsAndWorkScope = .needsAttention,
        presentationID: UUID? = nil,
        workID: UUID? = nil
    ) {
        lessonsAndWorkRequest = LessonsAndWorkRequest(
            scope: scope,
            presentationID: presentationID,
            workID: workID
        )
        selectedNavItem = .planningAgenda
    }

    func consumeLessonsAndWorkRequest() -> LessonsAndWorkRequest? {
        defer { lessonsAndWorkRequest = nil }
        return lessonsAndWorkRequest
    }

    /// Kept as a source-compatible bridge for Today and older call sites.
    func navigateToPresentationFollowUps() {
        navigateToLessonsAndWork(.needsAttention)
    }

    /// Open Ask AI and submit a question chosen from the notebook companion.
    func requestAIQuestion(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            selectedNavItem = .askAI
            return
        }
        pendingAIQuestion = trimmed
        selectedNavItem = .askAI
    }

    /// Returns a queued companion question exactly once.
    func consumePendingAIQuestion() -> String? {
        defer { pendingAIQuestion = nil }
        return pendingAIQuestion
    }

    /// Navigate to checklist with optional area/sequence pre-selection
    func navigateToChecklist(area: String, sequence: String? = nil) {
        checklistFilterArea = area
        checklistFilterSequence = sequence
        selectedNavItem = .planningChecklist
    }

    /// Trigger planning inbox refresh
    func refreshPlanningInbox() {
        planningInboxRefreshTrigger = UUID()
    }
    
    /// Clear current navigation destination
    func clearNavigation() {
        navigationDestination = nil
    }

    /// Signal that app data will be replaced
    func signalAppDataWillBeReplaced() {
        appDataWillBeReplaced = true
        // Reset after a brief moment to allow observers to react
        Task { @MainActor in
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
        Task { @MainActor in
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
    @MainActor static let defaultValue = AppRouter.shared
}

extension EnvironmentValues {
    var appRouter: AppRouter {
        get { self[AppRouterKey.self] }
        set { self[AppRouterKey.self] = newValue }
    }
}
