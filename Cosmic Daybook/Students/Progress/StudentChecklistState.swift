import Foundation

// MARK: - Display Status

/// Reason a student is blocked from progressing to the next lesson.
nonisolated public enum BlockingReason: Sendable, Equatable {
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

/// Where a child stands on a lesson: one rung of the ladder the Class Grid's mark draws
/// (`ChecklistMark`) in all four views, lowest first. Blue rungs are started, green is done,
/// orange is "act on it". Three Years uses the five rungs it can read (Not yet, Presented,
/// Practicing, Reviewing, Mastered); the Checklist adds Ready and Planned.
nonisolated public enum ChecklistDisplayStatus: Sendable, Hashable, CaseIterable, Comparable {
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

    /// Lowest first, in case order: a row's furthest mark is the largest.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .notReady: 0
        case .ready: 1
        case .planned: 2
        case .presented: 3
        case .practicing: 4
        case .reviewing: 5
        case .mastered: 6
        }
    }

    /// The one ladder every progress screen climbs (the Class Grid's four views, the child's
    /// Three-Year View, the student page's track timeline): the highest rung reached,
    /// mastered > reviewing > practicing > presented > planned, then ready or not yet ready by
    /// `blockingReason`. Only a mastery mark is Mastered; closed work without one is Reviewing,
    /// however it closed. Practice sessions count where a screen reads them (Three Years): one
    /// is Practicing, three are Reviewing.
    public static func resolve( // swiftlint:disable:this function_parameter_count
        isMastered: Bool,
        hasReviewWork: Bool,
        allWorkClosed: Bool,
        hasActiveWork: Bool,
        practiceSessions: Int = 0,
        isPresented: Bool,
        isPlanned: Bool,
        blockingReason: BlockingReason = .none
    ) -> ChecklistDisplayStatus {
        if isMastered { return .mastered }
        if hasReviewWork || allWorkClosed || practiceSessions >= 3 { return .reviewing }
        if hasActiveWork || practiceSessions >= 1 { return .practicing }
        if isPresented { return .presented }
        if isPlanned { return .planned }
        return blockingReason == .none ? .ready : .notReady
    }

    /// `resolve` from a child's work rows on the lesson, in any order.
    public static func resolve(
        isMastered: Bool,
        workStatuses: [WorkStatus],
        practiceSessions: Int = 0,
        isPresented: Bool,
        isPlanned: Bool,
        blockingReason: BlockingReason = .none
    ) -> ChecklistDisplayStatus {
        resolve(
            isMastered: isMastered,
            hasReviewWork: workStatuses.contains(.review),
            allWorkClosed: !workStatuses.isEmpty && workStatuses.allSatisfy(\.isClosed),
            hasActiveWork: workStatuses.contains(.active),
            practiceSessions: practiceSessions,
            isPresented: isPresented,
            isPlanned: isPlanned,
            blockingReason: blockingReason
        )
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
    /// A year-plan entry still waiting for this lesson (planned, not yet promoted to a
    /// presentation). It counts as Planned, as on the Groups page and in the ready queue
    /// (`PresentationRecordIndex.openPlanByLesson`), not Ready.
    public let isOnYearPlan: Bool
    public let blockingReason: BlockingReason
    /// The child has a mastery mark on the lesson (see `ChecklistDisplayStatus.mastered`).
    public let isMastered: Bool
    /// A Ready cell that is Ready, check first: what to look at on the lesson before
    /// (`ReadyForNextEngine.readiness(of:)`), e.g. "2 pieces of work still open". Empty
    /// otherwise.
    public let checkFirstReasons: [String]

    /// The highest rung reached: mastered > reviewing > practicing > presented > planned,
    /// then ready or not yet ready by the blocking reason. Closed work counts as Reviewing
    /// until the lesson carries a mastery mark; a mark is Mastered with or without work.
    public var displayStatus: ChecklistDisplayStatus {
        .resolve(
            isMastered: isMastered,
            hasReviewWork: isWorkReview,
            allWorkClosed: isComplete,
            hasActiveWork: isWorkActive,
            isPresented: isPresented,
            isPlanned: isScheduled || isOnYearPlan,
            blockingReason: blockingReason
        )
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
        isOnYearPlan: Bool = false,
        blockingReason: BlockingReason = .none,
        isMastered: Bool = false,
        checkFirstReasons: [String] = []
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
        self.isOnYearPlan = isOnYearPlan
        self.blockingReason = blockingReason
        self.isMastered = isMastered
        self.checkFirstReasons = checkFirstReasons
    }
}
