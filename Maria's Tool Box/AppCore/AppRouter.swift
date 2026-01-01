//
//  AppRouter.swift
//  Maria's Tool Box
//
//  Navigation coordinator for SwiftUI navigation patterns
//  Replaces NotificationCenter-based navigation with type-safe routing
//

import SwiftUI
import Combine

/// Central navigation coordinator for the app
/// Provides type-safe navigation actions and state management
@MainActor
class AppRouter: ObservableObject {
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
    
    // MARK: - Published State
    
    /// Current navigation destination to present
    @Published var navigationDestination: NavigationDestination? = nil
    
    /// Plan lesson request
    @Published var planLessonRequest: PlanLessonRequest? = nil
    
    /// Tab selection for root view
    @Published var selectedTab: RootView.Tab? = nil
    
    /// Students mode selection
    @Published var studentsMode: String? = nil
    
    /// Refresh trigger for planning inbox
    @Published var planningInboxRefreshTrigger: UUID = UUID()
    
    /// App lifecycle events
    @Published var appDataWillBeReplaced: Bool = false
    @Published var appDataDidRestore: Bool = false
    
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
    
    /// Navigate to a specific tab
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.appDataWillBeReplaced = false
        }
    }
    
    /// Signal that app data did restore
    func signalAppDataDidRestore() {
        appDataDidRestore = true
        // Reset after a brief moment to allow observers to react
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.appDataDidRestore = false
        }
    }
}

/// Environment key for AppRouter
struct AppRouterKey: EnvironmentKey {
    static let defaultValue = AppRouter.shared
}

extension EnvironmentValues {
    var appRouter: AppRouter {
        get { self[AppRouterKey.self] }
        set { self[AppRouterKey.self] = newValue }
    }
}

