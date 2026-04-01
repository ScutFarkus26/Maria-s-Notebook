import Foundation

// MARK: - Snapshot

/// Immutable value-type snapshot of a CDLessonAssignment for use in SwiftUI and async contexts.
struct LessonAssignmentSnapshot: Identifiable, Sendable {
    let id: UUID
    let lessonID: UUID
    let studentIDs: [UUID]
    let createdAt: Date
    let scheduledFor: Date?
    let presentedAt: Date?
    let state: LessonAssignmentState
    let notes: String
    let needsPractice: Bool
    let needsAnotherPresentation: Bool
    let followUpWork: String
    let manuallyUnblocked: Bool

    var isScheduled: Bool { scheduledFor != nil }
    var isGiven: Bool { state == .presented }
    var isPresented: Bool { state == .presented }
}

// MARK: - State Enum

/// Lifecycle states for a presentation.
enum LessonAssignmentState: String, Codable, CaseIterable, Sendable {
    /// Created but not yet scheduled.
    case draft

    /// Has a scheduled date for presentation.
    case scheduled

    /// Has been given to students (historical record).
    case presented
}

// MARK: - Public Type Aliases

/// Public alias for the unified presentation model.
/// Use this in code for cleaner semantics - "Presentation" is what teachers call it.
typealias Presentation = CDLessonAssignment

/// Public alias for presentation state.
typealias PresentationState = LessonAssignmentState
