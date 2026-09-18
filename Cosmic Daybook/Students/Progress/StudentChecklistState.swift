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

    public var color: SwiftUI.Color {
        switch self {
        case .none: return .clear
        case .prerequisiteNotPresented: return .red
        case .practiceRequired: return .orange
        case .confirmationRequired: return .purple
        case .practiceAndConfirmation: return .red
        }
    }
}

/// Resolved display status for a checklist cell, ordered by priority.
public enum ChecklistDisplayStatus: Sendable {
    case empty
    case scheduled
    case presented
    case practicing
    case reviewing
    case proficient

    public var iconName: String {
        switch self {
        case .proficient:  return "checkmark.circle.fill"
        case .reviewing:   return "eye.fill"
        case .practicing:  return "pencil"
        case .presented:   return "checkmark"
        case .scheduled:   return "calendar"
        case .empty:       return "circle"
        }
    }

    public var color: SwiftUI.Color {
        switch self {
        case .proficient:  return .green
        case .reviewing:   return .yellow
        case .practicing:  return .blue
        case .presented:   return .blue
        case .scheduled:   return .orange
        case .empty:       return .gray
        }
    }

    public var label: String {
        switch self {
        case .proficient:  return "Mastered"
        case .reviewing:   return "Reviewing"
        case .practicing:  return "Practicing"
        case .presented:   return "Presented"
        case .scheduled:   return "Scheduled"
        case .empty:       return "Not Started"
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

    /// Resolved display status, priority: proficient > reviewing > practicing > presented > scheduled > empty
    public var displayStatus: ChecklistDisplayStatus {
        if isComplete { return .proficient }
        if isWorkReview { return .reviewing }
        if isWorkActive { return .practicing }
        if isPresented { return .presented }
        if isScheduled { return .scheduled }
        return .empty
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
        blockingReason: BlockingReason = .none
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
    }
}
