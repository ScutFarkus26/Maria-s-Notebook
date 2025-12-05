import SwiftUI

struct WeekGrid: View {
    @Environment(\.calendar) private var calendar
    let days: [Date]
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let onSelectLesson: (StudentLesson) -> Void
    let onQuickActions: (StudentLesson) -> Void
    let onPlanNext: (StudentLesson) -> Void

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
        LazyVGrid(columns: columns, alignment: .leading, spacing: UIConstants.gridColumnSpacing) {
            ForEach(days, id: \.self) { day in
                DayColumn(day: day, availableHeight: availableHeight, onSelectLesson: onSelectLesson, onQuickActions: onQuickActions, onPlanNext: onPlanNext)
            }
        }
    }
}
