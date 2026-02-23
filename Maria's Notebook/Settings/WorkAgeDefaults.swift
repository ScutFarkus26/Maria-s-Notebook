import Foundation

/// Defaults for thresholds and colors used by the Work age indicator.
/// Mirrors `LessonAgeDefaults` unless overridden.
struct WorkAgeDefaults {
    // Thresholds
    static let warningDays: Int = LessonAgeDefaults.warningDays
    static let overdueDays: Int = LessonAgeDefaults.overdueDays

    // Default colors (sRGB hex with alpha)
    static let freshColorHex: String = LessonAgeDefaults.freshColorHex
    static let warningColorHex: String = LessonAgeDefaults.warningColorHex
    static let overdueColorHex: String = LessonAgeDefaults.overdueColorHex
}
