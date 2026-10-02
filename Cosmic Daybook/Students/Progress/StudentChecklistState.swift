import Foundation

// MARK: - Display Status

/// Reason a student is blocked from progressing to the next lesson.
public enum BlockingReason: Sendable, Equatable {
    /// No blocking — student can proceed.
    case none
    /// The preceding lesson hasn't been presented yet.
    case prerequisiteNotPresented
    /// Practice work is required but not complete.
    case practiceRequired
    /// Teacher confirmation/proficiency check is needed.
    case confirmationRequired
    /// Both practice and confirmation are needed.
    case practiceAndConfirmation

    public var label: String {
        switch self {
        case .none: return ""
        case .prerequisiteNotPresented: return "Prerequisite needed"
        case .practiceRequired: return "Needs practice"
        case .confirmationRequired: return "Needs confirmation"
        case .practiceAndConfirmation: return "Needs practice & confirmation"
        }
    }

    public var iconName: String {
        switch self {
        case .none: return ""
        case .prerequisiteNotPresented: return "lock.fill"
        case .practiceRequired: return "hourglass"
        case .confirmationRequired: return "hand.raised.fill"
        case .practiceAndConfirmation: return "exclamationmark.lock.fill"
        }
    }
}

/// Where a child stands on a checklist cell: one rung of the ladder the cell's mark draws
/// (`ChecklistMark`), lowest first. Blue rungs are started, green is done, orange is "act on it".
public enum ChecklistDisplayStatus: Sendable, Hashable, CaseIterable {
    /// Not presented, and the lesson before it still blocks it (`blockingReason != .none`).
    case notReady
    /// Not presented, not planned, nothing blocking it.
    case ready
    /// On a plan: the Inbox or a dated presentation.
    case planned
    case presented
    /// Open practice work.
    case practicing
    /// Work in review, or work closed without a mastery mark.
    case reviewing
    /// A mastery mark: the child's `CDLessonPresentation` is proficient or has `masteredAt`.
    case mastered

    public var label: String {
        switch self {
        case .notReady:   return "Not yet ready"
        case .ready:      return "Ready"
        case .planned:    return "Planned"
        case .presented:  return "Presented"
        case .practicing: return "Practicing"
        case .reviewing:  return "Reviewing"
        case .mastered:   return "Mastered"
        }
    }
}

import SwiftUI
import CoreData

public struct StudentChecklistRowState: Identifiable, Equatable {
    public var id: UUID { lessonID }
    public let lessonID: UUID
    public let plannedItemID: UUID?
    public let presentationLogID: UUID?
    public let contractID: UUID?
    public let isScheduled: Bool
    public let isPresented: Bool
    public let isActive: Bool
    public let isComplete: Bool
    public let isWorkActive: Bool
    public let isWorkReview: Bool
    public let lastActivityDate: Date?
    public let isStale: Bool
    public let isInboxPlan: Bool
    public let blockingReason: BlockingReason
    /// The child has a mastery mark on the lesson (see `ChecklistDisplayStatus.mastered`).
    public let isMastered: Bool

    /// The highest rung reached: mastered > reviewing > practicing > presented > planned,
    /// then ready or not yet ready by the blocking reason. Closed work counts as Reviewing
    /// until the lesson carries a mastery mark; a mark is Mastered with or without work.
    public var displayStatus: ChecklistDisplayStatus {
        if isMastered { return .mastered }
        if isWorkReview || isComplete { return .reviewing }
        if isWorkActive { return .practicing }
        if isPresented { return .presented }
        if isScheduled { return .planned }
        return blockingReason == .none ? .ready : .notReady
    }

    /// Open work that hasn't been touched in a while, on a lesson not yet mastered.
    public var needsCheckIn: Bool {
        isStale && !isMastered
    }

    public init(
        lessonID: UUID,
        plannedItemID: UUID?,
        presentationLogID: UUID?,
        contractID: UUID?,
        isScheduled: Bool,
        isPresented: Bool,
        isActive: Bool,
        isComplete: Bool,
        isWorkActive: Bool = false,
        isWorkReview: Bool = false,
        lastActivityDate: Date?,
        isStale: Bool,
        isInboxPlan: Bool = false,
        blockingReason: BlockingReason = .none,
        isMastered: Bool = false
    ) {
        self.lessonID = lessonID
        self.plannedItemID = plannedItemID
        self.presentationLogID = presentationLogID
        self.contractID = contractID
        self.isScheduled = isScheduled
        self.isPresented = isPresented
        self.isActive = isActive
        self.isComplete = isComplete
        self.isWorkActive = isWorkActive
        self.isWorkReview = isWorkReview
        self.lastActivityDate = lastActivityDate
        self.isStale = isStale
        self.isInboxPlan = isInboxPlan
        self.blockingReason = blockingReason
        self.isMastered = isMastered
    }
}
