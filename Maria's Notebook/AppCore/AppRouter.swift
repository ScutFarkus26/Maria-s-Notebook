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
        case newLesson(defaultSubject: String?, defaultGroup: String?)
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
    
    // MARK: - State
    
    /// Current navigation destination to present
    var navigationDestination: NavigationDestination?
    
    /// Plan lesson request
    var planLessonRequest: PlanLessonRequest?
    
    /// Navigation item selection for root view (new primary navigation)
    var selectedNavItem: RootView.NavigationItem?
    
    /// Tab selection for root view (legacy - kept for backward compatibility)
    var selectedTab: RootView.Tab?
    
    /// Students mode selection
    var studentsMode: String?
    
    /// Checklist deep-link filters (consumed once by ChecklistViewModel)
    var checklistFilterSubject: String?
    var checklistFilterGroup: String?

    /// Refresh trigger for planning inbox
    var planningInboxRefreshTrigger: UUID = UUID()

    /// App lifecycle events
    var appDataWillBeReplaced: Bool = false
    var appDataDidRestore: Bool = false
    
    // MARK: - Navigation Methods
    
    /// Request to show new lesson sheet
    func requestNewLesson(defaultSubject: String? = nil, defaultGroup: String? = nil) {
        navigationDestination = .newLesson(defaultSubject: defaultSubject, defaultGroup: defaultGroup)
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
    
    /// Request to open attendance
    func requestOpenAttendance() {
        navigationDestination = .openAttendance
    }
    
    /// Request to open student detail
    func requestOpenStudentDetail(_ studentID: UUID) {
        navigationDestination = .openStudentDetail(studentID)
    }
    
    /// Request to show backfill
    func requestBackfillIsPresented() {
        navigationDestination = .backfillIsPresented
    }
    
    /// Request to show quick actions
    func requestQuickActions() {
        navigationDestination = .quickActions
    }
    
    /// Request to plan lesson for student on date
    func requestPlanLessonForStudentOnDate(studentID: UUID, date: Date) {
        planLessonRequest = PlanLessonRequest(studentID: studentID, date: date)
    }
    
    /// Navigate to a specific navigation item
    func navigateTo(_ item: RootView.NavigationItem) {
        selectedNavItem = item
    }

    /// Navigate to checklist with optional subject/group pre-selection
    func navigateToChecklist(subject: String, group: String? = nil) {
        checklistFilterSubject = subject
        checklistFilterGroup = group
        selectedNavItem = .planningChecklist
    }
    
    /// Navigate to a specific tab (legacy - kept for backward compatibility)
    func navigateToTab(_ tab: RootView.Tab) {
        selectedTab = tab
    }
    
    /// Set students mode
    func setStudentsMode(_ mode: String) {
        studentsMode = mode
    }
    
    /// Trigger planning inbox refresh
    func refreshPlanningInbox() {
        planningInboxRefreshTrigger = UUID()
    }
    
    /// Clear current navigation destination
    func clearNavigation() {
        navigationDestination = nil
    }
    
    /// Clear plan lesson request
    func clearPlanLessonRequest() {
        planLessonRequest = nil
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
