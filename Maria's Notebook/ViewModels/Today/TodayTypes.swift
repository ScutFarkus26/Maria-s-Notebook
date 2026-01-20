// TodayTypes.swift
// Shared types used by TodayViewModel and related components.

import Foundation

// MARK: - Schedule Item Types

/// Data structure for a scheduled check-in (explicit WorkPlanItem).
struct ScheduledWorkItem: Identifiable {
    let work: WorkModel
    let planItem: WorkPlanItem
    var id: UUID { planItem.id }
}

/// Data structure for a stale follow-up (implicit WorkModel aging).
struct FollowUpWorkItem: Identifiable {
    let work: WorkModel
    let daysSinceTouch: Int
    var id: UUID { work.id }
}

// MARK: - Attendance Summary

/// Lightweight counts shown in the Today header.
struct AttendanceSummary {
    var presentCount: Int = 0
    var tardyCount: Int = 0
    var absentCount: Int = 0
    var leftEarlyCount: Int = 0
}

// MARK: - Level Filter

/// Filter for Lower/Upper/All levels. Used to reduce the visible items across sections.
enum LevelFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case lower = "Lower"
    case upper = "Upper"

    var id: String { rawValue }

    func matches(_ level: Student.Level) -> Bool {
        switch self {
        case .all: return true
        case .lower: return level == .lower
        case .upper: return level == .upper
        }
    }
}
