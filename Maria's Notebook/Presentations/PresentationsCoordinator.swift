//
//  PresentationsCoordinator.swift
//  Maria's Notebook
//
//  Navigation coordinator for the Presentations menu
//  Centralizes all sheet/navigation state management following 2026 best practices
//

import Foundation
import SwiftUI
import CoreData

/// Centralized navigation coordinator for Presentations menu
/// Uses @Observable for automatic SwiftUI dependency tracking
@Observable
@MainActor
final class PresentationsCoordinator {

    // MARK: - Sheet Destinations

    /// Enum representing all possible sheet destinations in Presentations
    /// CDNote: Cannot conform to Sendable because SwiftData models are not Sendable
    enum Sheet: Identifiable {
        case lessonAssignmentDetail(CDLessonAssignment)
        case schedulePresentationFor(CDLesson)
        case postPresentation(CDLessonAssignment)
        case unifiedWorkflow(CDLessonAssignment)
        case lessonAssignmentHistory(CDLesson)

        var id: String {
            switch self {
            case .lessonAssignmentDetail(let la):
                return "lessonAssignDetail-\(la.id)"
            case .schedulePresentationFor(let lesson):
                return "schedulePres-\(lesson.id)"
            case .postPresentation(let la):
                return "postPres-\(la.id)"
            case .unifiedWorkflow(let la):
                return "workflow-\(la.id)"
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

    /// Present lesson assignment detail sheet
    func showLessonAssignmentDetail(_ lessonAssignment: CDLessonAssignment) {
        activeSheet = .lessonAssignmentDetail(lessonAssignment)
    }

    /// Present schedule presentation sheet
    func showSchedulePresentation(for lesson: CDLesson) {
        activeSheet = .schedulePresentationFor(lesson)
    }

    /// Present post-presentation workflow
    func showPostPresentation(_ lessonAssignment: CDLessonAssignment) {
        activeSheet = .postPresentation(lessonAssignment)
    }

    /// Present unified presentation workflow
    func showUnifiedWorkflow(_ lessonAssignment: CDLessonAssignment) {
        activeSheet = .unifiedWorkflow(lessonAssignment)
    }

    /// Present lesson assignment history
    func showLessonAssignmentHistory(for lesson: CDLesson) {
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
