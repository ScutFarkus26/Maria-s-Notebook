import Foundation
import UniformTypeIdentifiers

/// Unified drag payload for presentations (LessonAssignment) and work check-ins (WorkCheckIn)
/// Used in both PresentationsCalendarStrip and WorkAgendaCalendarPane
public enum UnifiedCalendarDragPayload: Equatable {
    case presentation(UUID)
    case workCheckIn(UUID)

    public var id: UUID {
        switch self {
        case .presentation(let id), .workCheckIn(let id): return id
        }
    }

    public var kind: String {
        switch self {
        case .presentation: return "presentation"
        case .workCheckIn: return "workCheckIn"
        }
    }

    public var stringRepresentation: String {
        switch self {
        case .presentation(let id): return "PRESENTATION:\(id.uuidString)"
        case .workCheckIn(let id): return "WORKCHECKIN:\(id.uuidString)"
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
        } else if let id = UUID(uuidString: trimmed) {
            // Backwards compatibility: plain UUID is treated as a presentation
            return .presentation(id)
        }
        return nil
    }
}
