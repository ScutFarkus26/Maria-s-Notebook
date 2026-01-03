// WorkPlanItem.swift
// New SwiftData model to plan check-ins for WorkContract without mutating Work itself.

import Foundation
import SwiftData

@Model
final class WorkPlanItem: Identifiable {
    enum Reason: String, Codable, CaseIterable, Identifiable {
        case progressCheck
        case dueDate
        case assessment
        case followUp
        case studentRequest
        case other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .progressCheck: return "Progress Check"
            case .dueDate: return "Due Date"
            case .assessment: return "Assessment"
            case .followUp: return "Follow Up"
            case .studentRequest: return "Student Request"
            case .other: return "Other"
            }
        }
        var icon: String {
            switch self {
            case .progressCheck: return "checkmark.circle"
            case .dueDate: return "calendar.badge.exclamationmark"
            case .assessment: return "doc.text.magnifyingglass"
            case .followUp: return "arrow.uturn.right.circle"
            case .studentRequest: return "person.wave.2"
            case .other: return "ellipsis.circle"
            }
        }
    }

    // Identity
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // Foreign key to WorkContract (store UUID for light coupling)
    // CloudKit compatibility: Store UUID as string
    var workID: String = ""

    // Planning info
    /// Normalized to start-of-day via AppCalendar.shared
    var scheduledDate: Date = Date()
    var reasonRaw: String?
    var note: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        workID: UUID,
        scheduledDate: Date,
        reason: Reason? = .progressCheck,
        note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        // CloudKit compatibility: Store UUID as string
        self.workID = workID.uuidString
        self.scheduledDate = scheduledDate
        self.reasonRaw = reason?.rawValue
        self.note = note
    }

    var reason: Reason? {
        get { reasonRaw.flatMap(Reason.init(rawValue:)) }
        set { reasonRaw = newValue?.rawValue }
    }
    
    // Computed property for backward compatibility with UUID
    var workIDUUID: UUID? {
        get { UUID(uuidString: workID) }
        set { workID = newValue?.uuidString ?? "" }
    }
    
    // Inverse relationship for Note.workPlanItem
    @Relationship(deleteRule: .cascade, inverse: \Note.workPlanItem) var notes: [Note]? = []
}

#if DEBUG
extension WorkPlanItem {
    var debugDescription: String {
        "WorkPlanItem(id=\(id), workID=\(workID), date=\(scheduledDate), reason=\(reasonRaw ?? "nil"))"
    }
}
#endif
