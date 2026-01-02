import SwiftUI

struct AppColors {
    static func color(forLevel level: Student.Level) -> Color {
        switch level {
        case .upper: return .pink
        case .lower: return .blue
        }
    }

    static func color(forSubject subject: String) -> Color {
        let key = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Common explicit mappings for clarity and cross-view consistency
        switch key {
        case "math", "mathematics": return .indigo
        case "language", "language arts": return .purple
        case "science": return .teal
        case "practical life": return .orange
        case "sensorial": return .pink
        case "geography": return .brown
        case "history": return .red
        case "art": return .cyan
        case "music": return .mint
        case "grace & courtesy", "grace and courtesy": return .yellow
        case "geometry": return .blue
        case "botany": return .green
        case "zoology": fallthrough
        case "reading": return .blue
        case "writing": return .orange
        default:
            return colorFromPalette(for: key)
        }
    }
    
    // MARK: - Color Palette
    
    /// Default color palette for unmapped subjects.
    /// Colors are selected deterministically based on subject name hash.
    private static let defaultColorPalette: [Color] = [
        .blue, .purple, .teal, .orange, .pink, .green, .indigo, .brown, .cyan, .mint, .yellow, .red
    ]
    
    /// Returns a color from the default palette based on the subject key's hash.
    /// This ensures consistent color assignment for the same subject name.
    private static func colorFromPalette(for key: String) -> Color {
        let index = abs(key.hashValue) % defaultColorPalette.count
        return defaultColorPalette[index]
    }
}
