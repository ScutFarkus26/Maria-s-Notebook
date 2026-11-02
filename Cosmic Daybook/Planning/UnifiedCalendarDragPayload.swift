import Foundation
import UniformTypeIdentifiers

/// Unified drag payload for calendar drag operations:
/// presentations (CDLessonAssignment), work check-ins (CDWorkCheckIn),
/// work items (CDWorkModel), and year plan entries (CDYearPlanEntry).
/// Used by the student Year Plan calendar and the Consolidate sheet's pills.
nonisolated public enum UnifiedCalendarDragPayload: Equatable {
    case presentation(UUID)
    case workCheckIn(UUID)
    case work(UUID)
    case yearPlanEntry(UUID)

    public var id: UUID {
        switch self {
        case .presentation(let id), .workCheckIn(let id), .work(let id), .yearPlanEntry(let id):
            return id
        }
    }

    public var kind: String {
        switch self {
        case .presentation: return "presentation"
        case .workCheckIn: return "workCheckIn"
        case .work: return "work"
        case .yearPlanEntry: return "yearPlanEntry"
        }
    }

    public var stringRepresentation: String {
        switch self {
        case .presentation(let id): return "PRESENTATION:\(id.uuidString)"
        case .workCheckIn(let id): return "WORKCHECKIN:\(id.uuidString)"
        case .work(let id): return "WORK:\(id.uuidString)"
        case .yearPlanEntry(let id): return "YEARPLAN:\(id.uuidString)"
        }
    }

    nonisolated public static func parse(_ s: String) -> UnifiedCalendarDragPayload? {
        // Only the first line: a string carrying several records reads as
        // the first of them.
        let firstLine = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
        let trimmed = firstLine.trimmed()
        if trimmed.hasPrefix("PRESENTATION:"), let id = UUID(uuidString: String(trimmed.dropFirst(13))) {
            return .presentation(id)
        } else if trimmed.hasPrefix("WORKCHECKIN:"), let id = UUID(uuidString: String(trimmed.dropFirst(12))) {
            return .workCheckIn(id)
        } else if trimmed.hasPrefix("WORK:"), let id = UUID(uuidString: String(trimmed.dropFirst(5))) {
            return .work(id)
        } else if trimmed.hasPrefix("YEARPLAN:"), let id = UUID(uuidString: String(trimmed.dropFirst(9))) {
            return .yearPlanEntry(id)
        } else if let id = UUID(uuidString: trimmed) {
            // Backwards compatibility: plain UUID is treated as a presentation
            return .presentation(id)
        }
        return nil
    }
}
