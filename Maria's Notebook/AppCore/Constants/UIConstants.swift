import SwiftUI

enum UIConstants {
    static let sidebarWidth: CGFloat = 280
    static let headerHorizontalPadding: CGFloat = 16
    static let headerVerticalPadding: CGFloat = 10

    static let contentHorizontalPadding: CGFloat = 16
    static let contentVerticalPadding: CGFloat = 20

    static let gridColumnSpacing: CGFloat = 24
    static let dayColumnSpacing: CGFloat = 14

    static let dayHeaderApproxHeight: CGFloat = 40
    static let labelHeight: CGFloat = 18
    static let minDropZoneTotalHeight: CGFloat = 220

    static let dropZoneCornerRadius: CGFloat = 18
    static let dropZoneStrokeDash: [CGFloat] = [6, 6]
    static let dropZoneInnerPadding: CGFloat = 12

    static let ageIndicatorWidth: CGFloat = 3

    static let morningHour: Int = 9
    static let afternoonHour: Int = 14

    static let planningWindowDays: Int = 5
    static let planningNavigationStepSchoolDays: Int = 7

    static let scheduleSpacingSeconds: Int = 1

    // MARK: - Sheet Sizes (macOS)

    /// Standardized sheet size presets for consistent macOS window sizing
    enum SheetSize {
        /// Large sheets for detail views (StudentDetail, WorkDetail)
        static let large = CGSize(width: 720, height: 640)
        /// Medium sheets for editors and complex forms
        static let medium = CGSize(width: 520, height: 560)
        /// Small sheets for simple dialogs
        static let small = CGSize(width: 420, height: 480)
        /// Compact sheets for minimal dialogs
        static let compact = CGSize(width: 400, height: 400)
        /// Note editor sheets
        static let note = CGSize(width: 480, height: 560)
    }
}
