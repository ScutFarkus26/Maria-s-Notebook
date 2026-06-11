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
