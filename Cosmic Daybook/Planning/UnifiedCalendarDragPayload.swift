import Foundation
import UniformTypeIdentifiers

/// Unified drag payload for all calendar drag operations:
/// presentations (CDLessonAssignment), work check-ins (CDWorkCheckIn),
/// work items (CDWorkModel), and year plan entries (CDYearPlanEntry).
/// Used across WeekPlanSection, WorkAgendaCalendarPane, planning views,
/// and the student Year Plan calendar.
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

    /// Joins several payloads into one drag string.
    ///
    /// A command-click selection drags as a single item carrying every record
    /// in it. One payload per line keeps the format backwards compatible:
    /// `parse` reads the first line, so a drop site that has not been taught
    /// about multi-drag still schedules the card the guide was dragging rather
    /// than failing to parse and silently doing nothing.
    nonisolated public static func joined(_ payloads: [UnifiedCalendarDragPayload]) -> String {
        payloads.map(\.stringRepresentation).joined(separator: "\n")
    }

    /// Every payload in a drag string, in order.
    nonisolated public static func parseAll(_ s: String) -> [UnifiedCalendarDragPayload] {
        s.split(whereSeparator: \.isNewline).compactMap { parse(String($0)) }
    }

    nonisolated public static func parse(_ s: String) -> UnifiedCalendarDragPayload? {
        // Only the first line: a multi-record drag reaching a single-record
        // drop site schedules the card under the pointer.
        let firstLine = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
        let trimmed = firstLine.trimmed()
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
        } else if trimmed.hasPrefix("YEARPLAN:"), let id = UUID(uuidString: String(trimmed.dropFirst(9))) {
            return .yearPlanEntry(id)
        } else if let id = UUID(uuidString: trimmed) {
            // Backwards compatibility: plain UUID is treated as a presentation
            return .presentation(id)
        }
        return nil
    }
}
