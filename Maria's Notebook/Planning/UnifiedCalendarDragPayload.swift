import Foundation
import UniformTypeIdentifiers

/// Unified drag payload for presentations (StudentLesson) and work check-ins (WorkCheckIn)
/// Used in both PresentationsCalendarStrip and WorkAgendaCalendarPane
public enum UnifiedCalendarDragPayload: Equatable {
    case studentLesson(UUID)
    case workCheckIn(UUID)
    
    public var id: UUID {
        switch self {
        case .studentLesson(let id), .workCheckIn(let id): return id
        }
    }
    
    public var kind: String {
        switch self {
        case .studentLesson: return "studentLesson"
        case .workCheckIn: return "workCheckIn"
        }
    }
    
    public var stringRepresentation: String {
        switch self {
        case .studentLesson(let id): return "STUDENTLESSON:\(id.uuidString)"
        case .workCheckIn(let id): return "WORKCHECKIN:\(id.uuidString)"
        }
    }
    
    nonisolated public static func parse(_ s: String) -> UnifiedCalendarDragPayload? {
        let trimmed = s.trimmed()
        if trimmed.hasPrefix("STUDENTLESSON:"), let id = UUID(uuidString: String(trimmed.dropFirst(14))) {
            return .studentLesson(id)
        } else if trimmed.hasPrefix("WORKCHECKIN:"), let id = UUID(uuidString: String(trimmed.dropFirst(12))) {
            return .workCheckIn(id)
        } else if let id = UUID(uuidString: trimmed) {
            // Backwards compatibility: plain UUID is treated as StudentLesson
            return .studentLesson(id)
        }
        return nil
    }
}
