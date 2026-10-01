//
//  PresentationsCoordinator.swift
//  Cosmic Daybook
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
final class PresentationsCoordinator {

    // MARK: - Sheet Destinations

    /// Enum representing all possible sheet destinations in Presentations
    /// CDNote: Cannot conform to Sendable because SwiftData models are not Sendable
    enum Sheet: Identifiable {
        case lessonAssignmentDetail(CDLessonAssignment)
        case schedulePresentationFor(CDLesson)
        /// Merge the presentations of one lesson (or, with nil, of every
        /// lesson that has more than one).
        case consolidatePresentations(lessonID: UUID?)

        var id: String {
            switch self {
            case .lessonAssignmentDetail(let la):
                return "lessonAssignDetail-\(la.id?.uuidString ?? "nil")"
            case .schedulePresentationFor(let lesson):
                return "schedulePres-\(lesson.id?.uuidString ?? "nil")"
            case .consolidatePresentations(let lessonID):
                return "consolidatePresentations-\(lessonID?.uuidString ?? "all")"
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

    /// Present the merge sheet for one lesson's presentations.
    func showMergeGroups(forLesson lessonID: UUID) {
        activeSheet = .consolidatePresentations(lessonID: lessonID)
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
