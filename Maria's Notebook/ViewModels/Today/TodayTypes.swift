// TodayTypes.swift
// Shared types used by TodayViewModel and related components.

import Foundation

// MARK: - Schedule Item Types

/// Data structure for a scheduled check-in (WorkCheckIn with .scheduled status).
/// Uses WorkCheckIn for scheduled work check-ins.
struct ScheduledWorkItem: Identifiable {
    let work: WorkModel
    let checkIn: WorkCheckIn
    var id: UUID { checkIn.id ?? UUID() }
}

/// Data structure for a stale follow-up (implicit WorkModel aging).
struct FollowUpWorkItem: Identifiable {
    let work: WorkModel
    let daysSinceTouch: Int
    var id: UUID { work.id ?? UUID() }
}

// MARK: - Agenda Item Types

/// The kind of item that can appear in the unified Today agenda.
enum AgendaItemType: String, Codable, Sendable {
    case lesson
    case meeting
    case scheduledWork
    case followUp
    case groupedScheduledWork
    case groupedFollowUp
}

/// A unified wrapper for items in the Today agenda.
/// Represents either a lesson or a work item (scheduled check-in or follow-up).
/// Grouped variants merge multiple students' work from the same lesson into one row.
enum AgendaItem: Identifiable {
    case lesson(LessonAssignment)
    case meeting(ScheduledMeeting)
    case scheduledWork(ScheduledWorkItem)
    case followUp(FollowUpWorkItem)
    case groupedScheduledWork([ScheduledWorkItem])
    case groupedFollowUp([FollowUpWorkItem])

    var id: UUID {
        switch self {
        case .lesson(let sl): return sl.id ?? UUID()
        case .meeting(let meeting): return meeting.id ?? UUID()
        case .scheduledWork(let item): return item.id
        case .followUp(let item): return item.id
        case .groupedScheduledWork(let items): return items.first?.id ?? UUID()
        case .groupedFollowUp(let items): return items.first?.id ?? UUID()
        }
    }

    var itemType: AgendaItemType {
        switch self {
        case .lesson: return .lesson
        case .meeting: return .meeting
        case .scheduledWork: return .scheduledWork
        case .followUp: return .followUp
        case .groupedScheduledWork: return .groupedScheduledWork
        case .groupedFollowUp: return .groupedFollowUp
        }
    }
}

// MARK: - Attendance Summary

/// Lightweight counts shown in the Today header.
struct AttendanceSummary: Equatable {
    var presentCount: Int = 0
    var tardyCount: Int = 0
    var absentCount: Int = 0
    var leftEarlyCount: Int = 0
}

// MARK: - Level Filter

/// Filter for Lower/Upper/All levels. Used to reduce the visible items across sections.
enum LevelFilter: String, CaseIterable, Identifiable, Sendable {
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
