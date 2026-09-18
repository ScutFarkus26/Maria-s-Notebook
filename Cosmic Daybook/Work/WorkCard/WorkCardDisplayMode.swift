import Foundation

/// Display modes for WorkCard
enum WorkCardDisplayMode {
    /// Grid card with age bar, title, student, status badge, context menu, drag support
    /// Used in: OpenWorkGrid, StudentOverviewTab work sections
    case grid

    /// List row with icon, title, subtitle, trailing badge
    /// Used in: OpenWorkListView, WorksLogView
    case list

    /// Capsule pill with color bar, lesson title, student chips
    /// Used in: TodayView scheduled items
    case pill

    /// Compact row with title and participant completion toggles
    /// Used in: LinkedWorkSection
    case compact
}
