import Foundation
import UniformTypeIdentifiers

// Reuse the same string payload semantics used in WorkAgendaBetaView ("WORK:<uuid>" or "CHECKIN:<uuid>")
public enum WorkAgendaDragPayload: Equatable {
    case work(UUID)
    case checkIn(UUID)

    public var id: UUID {
        switch self {
        case .work(let id), .checkIn(let id): return id
        }
    }

    public var kind: String {
        switch self {
        case .work: return "work"
        case .checkIn: return "checkin"
        }
    }

    public var stringRepresentation: String {
        switch self {
        case .work(let id): return "WORK:\(id.uuidString)"
        case .checkIn(let id): return "CHECKIN:\(id.uuidString)"
        }
    }

    nonisolated public static func parse(_ s: String) -> WorkAgendaDragPayload? {
        let trimmed = s.trimmed()
        if trimmed.hasPrefix("WORK:"), let id = UUID(uuidString: String(trimmed.dropFirst(5))) {
            return .work(id)
        } else if trimmed.hasPrefix("CHECKIN:"), let id = UUID(uuidString: String(trimmed.dropFirst(8))) {
            return .checkIn(id)
        } else if let id = UUID(uuidString: trimmed) {
            return .checkIn(id)
        }
        return nil
    }
}
