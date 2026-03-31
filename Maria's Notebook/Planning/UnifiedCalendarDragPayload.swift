import Foundation
import UniformTypeIdentifiers

/// Unified drag payload for all calendar drag operations:
/// presentations (CDLessonAssignment), work check-ins (CDWorkCheckIn), and work items (CDWorkModel).
/// Used across PresentationsCalendarStrip, WorkAgendaCalendarPane, and planning views.
public enum UnifiedCalendarDragPayload: Equatable {
    case presentation(UUID)
    case workCheckIn(UUID)
    case work(UUID)

    public var id: UUID {
        switch self {
        case .presentation(let id), .workCheckIn(let id), .work(let id): return id
        }
    }

    public var kind: String {
        switch self {
        case .presentation: return "presentation"
        case .workCheckIn: return "workCheckIn"
        case .work: return "work"
        }
    }

    public var stringRepresentation: String {
        switch self {
        case .presentation(let id): return "PRESENTATION:\(id.uuidString)"
        case .workCheckIn(let id): return "WORKCHECKIN:\(id.uuidString)"
        case .work(let id): return "WORK:\(id.uuidString)"
        }
    }

    nonisolated public static func parse(_ s: String) -> UnifiedCalendarDragPayload? {
        let trimmed = s.trimmed()
        if trimmed.hasPrefix("PRESENTATION:"), let id = UUID(uuidString: String(trimmed.dropFirst(13))) {
            return .presentation(id)
        } else if trimmed.hasPrefix("STUDENTLESSON:"), let id = UUID(uuidString: String(trimmed.dropFirst(14))) {
            // Legacy format support
            return .presentation(id)
        } else if trimmed.hasPrefix("WORKCHECKIN:"), let id = UUID(uuidString: String(trimmed.dropFirst(12))) {
            return .workCheckIn(id)
        } else if trimmed.hasPrefix("CHECKIN:"), let id = UUID(uuidString: String(trimmed.dropFirst(8))) {
            // Legacy format from WorkAgendaDragPayload
            return .workCheckIn(id)
        } else if trimmed.hasPrefix("WORK:"), let id = UUID(uuidString: String(trimmed.dropFirst(5))) {
            return .work(id)
        } else if let id = UUID(uuidString: trimmed) {
            // Backwards compatibility: plain UUID is treated as a presentation
            return .presentation(id)
        }
        return nil
    }
}
