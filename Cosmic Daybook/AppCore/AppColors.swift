import SwiftUI

struct AppColors {
    static func color(forLevel level: CDStudent.Level) -> Color {
        switch level {
        case .upper: return .pink
        case .lower: return .blue
        case .adolescent: return .orange
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func color(forArea area: String) -> Color {
        let key = area.normalizedForComparison()

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
        case "zoology", "reading": return .blue
        case "writing": return .orange
        default:
            return colorFromPalette(for: key)
        }
    }

    // MARK: - Color Palette

    /// Default color palette for unmapped areas.
    /// Colors are selected deterministically based on area name hash.
    private static let defaultColorPalette: [Color] = [
        .blue, .purple, .teal, .orange, .pink, .green, .indigo, .brown, .cyan, .mint, .yellow, .red
    ]

    /// Returns a color from the default palette based on the area key's hash.
    /// This ensures consistent color assignment for the same area name.
    private static func colorFromPalette(for key: String) -> Color {
        let index = abs(key.hashValue) % defaultColorPalette.count
        return defaultColorPalette[index]
    }

    // MARK: - Semantic Status Colors

    /// Red — destructive actions, errors, critical states
    static let destructive: Color = .red
    /// Orange — warnings, caution states
    static let warning: Color = .orange
    /// Green — success, completion, positive states
    static let success: Color = .green
    /// Blue — informational, neutral highlights
    static let info: Color = .blue
    /// Amber — scheduling conflicts / "heads up" planning cues. Distinct from `.warning` orange.
    /// Brighter in Dark Mode so it reads cleanly on a dark window, like the system colors.
    static let attention = Color(
        light: Color(red: 0.80, green: 0.55, blue: 0.10),
        dark: Color(red: 0.98, green: 0.76, blue: 0.28)
    )

    // MARK: - Presentation Status

    /// Discrete states a lesson assignment can be in within the planner.
    /// This ramp is kept separate from subject-area colors so status and
    /// content type are always visually distinguishable.
    enum PresentationStatus {
        /// Lesson is ready to present — no blocking work, within age thresholds.
        case ready
        /// Lesson is waiting on student work before it can be presented.
        case brewing
        /// Lesson was highlighted by "Suggest Next" as the recommended pick.
        case suggested
        /// Lesson has exceeded the age threshold (>14 school days in the inbox).
        case overdue
    }

    /// Returns a status color that never collides with any `color(forArea:)` value.
    /// Use this for left-border strips, status icons, chip accents, and the legend.
    static func color(for status: PresentationStatus) -> Color {
        switch status {
        case .ready:    return .green
        case .brewing:  return Color(
            light: Color(red: 0.88, green: 0.68, blue: 0.10),
            dark: Color(red: 1.0, green: 0.82, blue: 0.32)
        ) // amber, distinct from .orange; brighter in Dark Mode
        case .suggested: return .accentColor
        case .overdue:  return .red
        }
    }
}
