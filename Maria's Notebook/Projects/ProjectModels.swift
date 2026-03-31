import Foundation
import OSLog

// MARK: - Assignment Mode

/// Describes how work is assigned in a project session
public enum SessionAssignmentMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case uniform    // Everyone gets the same work (auto-assigned to all)
    case choice     // Teacher offers N works, students pick M

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .uniform: return "Uniform"
        case .choice: return "Student Choice"
        }
    }

    public var description: String {
        switch self {
        case .uniform: return "All students receive the same assignments"
        case .choice: return "Students choose from offered works"
        }
    }
}

// Local JSON helper to avoid cross-file dependency
struct LocalJSONStringList {
    private static let logger = Logger.projects
    nonisolated static func encode(_ arr: [String]) -> String {
        guard !arr.isEmpty else { return "" }
        do {
            let data = try JSONEncoder().encode(arr)
            if let s = String(data: data, encoding: .utf8) {
                return s
            }
        } catch {
            Self.logger.warning("Failed to encode string array: \(error)")
        }
        return ""
    }
    nonisolated static func decode(_ s: String) -> [String] {
        let trimmed = s.trimmed()
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        do {
            let arr = try JSONDecoder().decode([String].self, from: data)
            return arr
        } catch {
            Self.logger.warning("Failed to decode string array: \(error)")
            return []
        }
    }
}
