import Foundation
import SwiftUI

/// Categories for classroom supplies
enum SupplyCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case art = "Art"
    case math = "Math"
    case language = "Language"
    case science = "Science"
    case practicalLife = "Practical Life"
    case sensorial = "Sensorial"
    case geography = "Geography"
    case music = "Music"
    case office = "Office"
    case cleaning = "Cleaning"
    case firstAid = "First Aid"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .art: return "paintbrush"
        case .math: return "number"
        case .language: return "textformat"
        case .science: return "flask"
        case .practicalLife: return "hands.sparkles"
        case .sensorial: return "hand.point.up"
        case .geography: return "globe.americas"
        case .music: return "music.note"
        case .office: return "paperclip"
        case .cleaning: return "sparkles"
        case .firstAid: return "cross.case"
        case .other: return "shippingbox"
        }
    }
}

/// Represents the stock status of a supply
enum SupplyStatus: String, Codable, Sendable {
    case healthy = "Healthy"
    case low = "Low"
    case critical = "Critical"
    case outOfStock = "Out of Stock"

    var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .low: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.circle.fill"
        case .outOfStock: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .healthy: return .primary
        case .low: return .orange
        case .critical, .outOfStock: return .red
        }
    }
}
