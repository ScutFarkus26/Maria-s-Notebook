//
//  PresentationsCoordinator.swift
//  Maria's Notebook
//
//  Navigation coordinator for the Presentations menu
//  Centralizes all sheet/navigation state management following 2026 best practices
//

import Foundation
import SwiftUI

/// Centralized navigation coordinator for Presentations menu
/// Uses @Observable for automatic SwiftUI dependency tracking
@Observable
@MainActor
final class PresentationsCoordinator {
    
    // MARK: - Sheet Destinations
    
    /// Enum representing all possible sheet destinations in Presentations
    enum Sheet: Identifiable {
        case studentLessonDetail(StudentLesson)
        case schedulePresentationFor(Lesson)
        case postPresentation(StudentLesson)
        case unifiedWorkflow(StudentLesson)
        case lessonAssignmentDetail(LessonAssignment)
        case lessonAssignmentHistory(Lesson)
        
        var id: String {
            switch self {
            case .studentLessonDetail(let sl):
                return "studentLessonDetail-\(sl.id)"
            case .schedulePresentationFor(let lesson):
                return "schedulePres-\(lesson.id)"
            case .postPresentation(let sl):
                return "postPres-\(sl.id)"
            case .unifiedWorkflow(let sl):
                return "workflow-\(sl.id)"
            case .lessonAssignmentDetail(let la):
                return "lessonAssignDetail-\(la.id)"
            case .lessonAssignmentHistory(let lesson):
                return "lessonAssignHistory-\(lesson.id)"
            }
        }
    }
    
    // MARK: - State
    
    /// Currently active sheet (nil if no sheet presented)
    var activeSheet: Sheet?
    
    /// UI state flags
    var isCalendarMinimized: Bool = false
    var isInboxTargeted: Bool = false
    
    /// Selected student filter (for filtering presentations by student)
    var selectedStudentFilter: UUID?
    
    // MARK: - Initialization
    
    init() {
        // Initialize with default values
    }
    
    // MARK: - Navigation Actions
    
    /// Present student lesson detail sheet
    func showStudentLessonDetail(_ studentLesson: StudentLesson) {
        activeSheet = .studentLessonDetail(studentLesson)
    }
    
    /// Present schedule presentation sheet
    func showSchedulePresentation(for lesson: Lesson) {
        activeSheet = .schedulePresentationFor(lesson)
    }
    
    /// Present post-presentation workflow
    func showPostPresentation(_ studentLesson: StudentLesson) {
        activeSheet = .postPresentation(studentLesson)
    }
    
    /// Present unified presentation workflow
    func showUnifiedWorkflow(_ studentLesson: StudentLesson) {
        activeSheet = .unifiedWorkflow(studentLesson)
    }
    
    /// Present lesson assignment detail
    func showLessonAssignmentDetail(_ lessonAssignment: LessonAssignment) {
        activeSheet = .lessonAssignmentDetail(lessonAssignment)
    }
    
    /// Present lesson assignment history
    func showLessonAssignmentHistory(for lesson: Lesson) {
        activeSheet = .lessonAssignmentHistory(lesson)
    }
    
    /// Dismiss currently active sheet
    func dismissSheet() {
        activeSheet = nil
    }
    
    // MARK: - UI Actions
    
    /// Toggle calendar minimized state
    func toggleCalendar() {
        isCalendarMinimized.toggle()
    }
    
    /// Set inbox as drop target
    func setInboxTargeted(_ targeted: Bool) {
        isInboxTargeted = targeted
    }
    
    /// Set selected student filter
    func filterByStudent(_ studentID: UUID?) {
        selectedStudentFilter = studentID
    }
    
    /// Clear student filter
    func clearStudentFilter() {
        selectedStudentFilter = nil
    }
}
