import Foundation
import UniformTypeIdentifiers

/// Unified drag payload for both presentations (StudentLesson) and work (WorkPlanItem)
/// Used in both PresentationsCalendarStrip and WorkAgendaCalendarPane
public enum UnifiedCalendarDragPayload: Equatable {
    case studentLesson(UUID)
    case workPlanItem(UUID)
    
    public var id: UUID {
        switch self {
        case .studentLesson(let id), .workPlanItem(let id): return id
        }
    }
    
    public var kind: String {
        switch self {
        case .studentLesson: return "studentLesson"
        case .workPlanItem: return "workPlanItem"
        }
    }
    
    public var stringRepresentation: String {
        switch self {
        case .studentLesson(let id): return "STUDENTLESSON:\(id.uuidString)"
        case .workPlanItem(let id): return "WORKPLANITEM:\(id.uuidString)"
        }
    }
    
    public static func parse(_ s: String) -> UnifiedCalendarDragPayload? {
        let trimmed = s.trimmed()
        if trimmed.hasPrefix("STUDENTLESSON:"), let id = UUID(uuidString: String(trimmed.dropFirst(14))) {
            return .studentLesson(id)
        } else if trimmed.hasPrefix("WORKPLANITEM:"), let id = UUID(uuidString: String(trimmed.dropFirst(13))) {
            return .workPlanItem(id)
        } else if let id = UUID(uuidString: trimmed) {
            // Backwards compatibility: plain UUID is treated as StudentLesson
            return .studentLesson(id)
        }
        return nil
    }
}
