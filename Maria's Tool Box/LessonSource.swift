import Foundation

enum LessonSource: String, Codable, CaseIterable, Identifiable {
    case album
    case personal
    var id: String { rawValue }

    var label: String {
        switch self {
        case .album: return "Album"
        case .personal: return "Personal"
        }
    }
}

enum PersonalLessonKind: String, Codable, CaseIterable, Identifiable {
    case personal
    case observation
    case adaptation
    case studentRequested
    case external
    var id: String { rawValue }

    var label: String {
        switch self {
        case .personal: return "Personal"
        case .observation: return "Observation"
        case .adaptation: return "Adaptation"
        case .studentRequested: return "Student Request"
        case .external: return "External"
        }
    }

    var badgeLabel: String { label }
}
