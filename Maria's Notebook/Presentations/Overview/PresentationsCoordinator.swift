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
        case consolidatePresentations

        var id: String {
            switch self {
            case .lessonAssignmentDetail(let la):
                return "lessonAssignDetail-\(la.id?.uuidString ?? "nil")"
            case .schedulePresentationFor(let lesson):
                return "schedulePres-\(lesson.id?.uuidString ?? "nil")"
            case .postPresentation(let la):
                return "postPres-\(la.id?.uuidString ?? "nil")"
            case .unifiedWorkflow(let la):
                return "workflow-\(la.id?.uuidString ?? "nil")"
            case .lessonAssignmentHistory(let lesson):
                return "lessonAssignHistory-\(lesson.id?.uuidString ?? "nil")"
            case .consolidatePresentations:
                return "consolidatePresentations"
            }
        }
    }

    // MARK: - State

    /// Currently active sheet (nil if no sheet presented)
    var activeSheet: Sheet?

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

    /// Present consolidate-duplicates sheet
    func showConsolidatePresentations() {
        activeSheet = .consolidatePresentations
    }

    /// Dismiss currently active sheet
    func dismissSheet() {
        activeSheet = nil
    }

    // MARK: - UI Actions

    /// Set selected student filter
    func filterByStudent(_ studentID: UUID?) {
        selectedStudentFilter = studentID
    }

    /// Clear student filter
    func clearStudentFilter() {
        selectedStudentFilter = nil
    }
}
