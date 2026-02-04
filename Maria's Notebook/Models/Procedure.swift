import Foundation
import SwiftData

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

    var icon: String {
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

    var description: String {
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

/// A documented classroom procedure
@Model
final class Procedure: Identifiable {
    /// Unique identifier
    var id: UUID = UUID()

    /// Title of the procedure
    var title: String = ""

    /// Brief summary shown in list views
    var summary: String = ""

    /// Full content in Markdown format
    var content: String = ""

    /// Category stored as raw string for CloudKit compatibility
    @RawCodable var category: ProcedureCategory = .other

    /// Icon name (SF Symbol or emoji)
    var icon: String = ""

    /// IDs of related procedures (stored as comma-separated string for CloudKit)
    private var relatedProcedureIDsRaw: String = ""

    /// When this procedure was created
    var createdAt: Date = Date()

    /// When this procedure was last modified
    var modifiedAt: Date = Date()

    /// Computed property for related procedure IDs
    var relatedProcedureIDs: [String] {
        get {
            guard !relatedProcedureIDsRaw.isEmpty else { return [] }
            return relatedProcedureIDsRaw.components(separatedBy: ",")
        }
        set {
            relatedProcedureIDsRaw = newValue.joined(separator: ",")
        }
    }

    /// Display icon - uses custom icon if set, otherwise category default
    var displayIcon: String {
        icon.isEmpty ? category.icon : icon
    }

    init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        content: String = "",
        category: ProcedureCategory = .other,
        icon: String = "",
        relatedProcedureIDs: [String] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.content = content
        self.category = category
        self.icon = icon
        self.relatedProcedureIDsRaw = relatedProcedureIDs.joined(separator: ",")
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Updates the modification timestamp
    func touch() {
        modifiedAt = Date()
    }
}
