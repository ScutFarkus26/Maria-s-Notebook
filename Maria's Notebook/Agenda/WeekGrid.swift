import SwiftUI

struct WeekGrid: View {
    @Environment(\.calendar) private var calendar
    let days: [Date]
    let allLessonAssignments: [CDLessonAssignment]
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let onSelectLesson: (CDLessonAssignment) -> Void
    let onQuickActions: (CDLessonAssignment) -> Void
    let onPlanNext: (CDLessonAssignment) -> Void

    private var columns: [GridItem] {
        let minWidth: CGFloat = 240
        let maxWidth: CGFloat = 300
        let spacing: CGFloat = UIConstants.gridColumnSpacing
        let columnsCount = max(1, days.count)
        let totalSpacing = spacing * CGFloat(columnsCount - 1)
        let contentWidth = max(0, availableWidth - totalSpacing)
        let computed = contentWidth / CGFloat(columnsCount)
        let itemWidth = min(max(computed, minWidth), maxWidth)
        return Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columnsCount)
    }

    var body: some View {
        // Pre-group lessons by day once so each DayColumn receives only its own slice,
        // eliminating the per-column, per-render filter over the full week array.
        let byDay = Dictionary(
            grouping: allLessonAssignments,
            by: { AppCalendar.startOfDay($0.scheduledFor ?? .distantPast) }
        )
        LazyVGrid(columns: columns, alignment: .leading, spacing: UIConstants.gridColumnSpacing) {
            ForEach(days, id: \.self) { day in
                let dayStart = AppCalendar.startOfDay(day)
                DayColumn(
                    day: day,
                    lessonAssignments: byDay[dayStart, default: []],
                    availableHeight: availableHeight,
                    onSelectLesson: onSelectLesson,
                    onQuickActions: onQuickActions,
                    onPlanNext: onPlanNext
                )
            }
        }
    }
}
