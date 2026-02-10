import Foundation

/// Centralized label functions for practice session quality metrics and understanding levels
/// Used across PracticeSessionSheet, QuickPracticeSessionSheet, and PracticeSessionComponents
enum PracticeSessionLabels {

    // MARK: - Quality Labels

    nonisolated static func qualityLabel(for level: Int) -> String {
        switch level {
        case 1: return "Distracted"
        case 2: return "Minimal"
        case 3: return "Adequate"
        case 4: return "Good"
        case 5: return "Excellent"
        default: return ""
        }
    }

    // MARK: - Independence Labels

    nonisolated static func independenceLabel(for level: Int) -> String {
        switch level {
        case 1: return "Constant Help"
        case 2: return "Frequent Guidance"
        case 3: return "Some Support"
        case 4: return "Mostly Independent"
        case 5: return "Fully Independent"
        default: return ""
        }
    }

    // MARK: - Understanding Labels

    nonisolated static func understandingLabel(for level: Int) -> String {
        switch level {
        case 1: return "Struggling"
        case 2: return "Needs Support"
        case 3: return "Developing"
        case 4: return "Proficient"
        case 5: return "Mastered"
        default: return ""
        }
    }
}
