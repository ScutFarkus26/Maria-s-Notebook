import Foundation

/// Categories for classroom procedures
enum ProcedureCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case dailyRoutines = "Daily Routines"
    case safety = "Safety & Emergency"
    case specialSchedules = "Special Schedules"
    case transitions = "Transitions"
    case materials = "Materials & Cleanup"
    case communication = "Communication"
    case behavioral = "Behavioral"
    case other = "Other"

    var id: String { rawValue }

    nonisolated var icon: String {
        switch self {
        case .dailyRoutines: return "sun.horizon"
        case .safety: return "exclamationmark.shield"
        case .specialSchedules: return "calendar.badge.clock"
        case .transitions: return "arrow.left.arrow.right"
        case .materials: return "tray.2"
        case .communication: return "message"
        case .behavioral: return "hand.raised"
        case .other: return "doc.text"
        }
    }

    nonisolated var description: String {
        switch self {
        case .dailyRoutines: return "Morning arrival, lunch, dismissal, etc."
        case .safety: return "Fire drills, lockdowns, medical emergencies"
        case .specialSchedules: return "Friday schedules, early release, field trips"
        case .transitions: return "Moving between activities and spaces"
        case .materials: return "Using and caring for classroom materials"
        case .communication: return "Parent communication, announcements"
        case .behavioral: return "Conflict resolution, classroom expectations"
        case .other: return "Other classroom procedures"
        }
    }
}
