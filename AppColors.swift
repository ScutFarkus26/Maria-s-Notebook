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
        switch key {
        case "math": return .blue
        case "language": return .purple
        case "science": return .teal
        default: return .accentColor
        }
    }
}
