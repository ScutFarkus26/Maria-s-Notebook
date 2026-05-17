import SwiftUI

/// Color presets for an Initiative. Stored on `CDInitiative.colorRaw` as the case name.
enum InitiativeColor: String, CaseIterable, Identifiable, Sendable {
    case blue, indigo, purple, pink, red, orange, yellow, green, teal, gray

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .blue:   return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink:   return .pink
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .teal:   return .teal
        case .gray:   return .gray
        }
    }

    static let defaultValue: InitiativeColor = .blue

    static func from(raw: String?) -> InitiativeColor {
        guard let raw, let value = InitiativeColor(rawValue: raw) else { return .defaultValue }
        return value
    }
}

/// Common SF Symbols suggested for Initiatives. Stored on `CDInitiative.symbol` as the raw symbol name.
enum InitiativeSymbol: String, CaseIterable, Identifiable, Sendable {
    case target = "target"
    case flag = "flag.checkered"
    case doc = "doc.text"
    case bus = "bus"
    case figureWalk = "figure.walk"
    case backpack = "backpack"
    case calendar = "calendar"
    case sparkles = "sparkles"
    case checklist = "checklist.checked"
    case envelope = "envelope"

    var id: String { rawValue }

    static let defaultValue: InitiativeSymbol = .target
}

/// Area suggestions surfaced in pickers. Stored on `CDInitiative.area` as a free-form String.
enum InitiativeAreaSuggestion {
    static let common: [String] = [
        "Reports",
        "Trips",
        "Admin",
        "Parents",
        "Curriculum",
        "Personal"
    ]
}
