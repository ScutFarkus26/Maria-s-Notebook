import Foundation

enum LessonSource: String, Codable, CaseIterable, Identifiable, Sendable {
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

enum LessonFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case story
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .story: return "Story"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "book.closed"
        case .story: return "book.pages"
        }
    }
}

enum PersonalLessonKind: String, Codable, CaseIterable, Identifiable, Sendable {
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

enum ProgressionOverride: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit
    case yes
    case no
    var id: String { rawValue }

    var label: String {
        switch self {
        case .inherit: return "From Group"
        case .yes: return "Yes"
        case .no: return "No"
        }
    }
}
