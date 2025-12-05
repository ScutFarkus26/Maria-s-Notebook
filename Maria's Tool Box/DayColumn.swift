import SwiftUI
import SwiftData

struct DayColumn: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Query private var studentLessons: [StudentLesson]
    let day: Date
    let availableHeight: CGFloat
    let onSelectLesson: (StudentLesson) -> Void
    let onQuickActions: (StudentLesson) -> Void
    let onPlanNext: (StudentLesson) -> Void

    private var dropZoneHeight: CGFloat {
        let overhead: CGFloat = UIConstants.dayHeaderApproxHeight + (UIConstants.labelHeight * 2) + (UIConstants.dayColumnSpacing * 3)
        let remaining = max(UIConstants.minDropZoneTotalHeight, availableHeight - overhead)
        return remaining / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.dayColumnSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(dayNumber)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                if SchoolCalendar.isNonSchoolDay(day, using: modelContext) {
                    Text("No School")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(0.15)))
                        .foregroundStyle(.red)
                }
            }
            .padding(.bottom, 2)

            Text("Morning")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            DropZone(allStudentLessons: studentLessons, day: day, period: PlanningDayPeriod.morning, onSelectLesson: onSelectLesson, onQuickActions: onQuickActions, onPlanNext: onPlanNext)
                .frame(height: dropZoneHeight)

            Text("Afternoon")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            DropZone(allStudentLessons: studentLessons, day: day, period: PlanningDayPeriod.afternoon, onSelectLesson: onSelectLesson, onQuickActions: onQuickActions, onPlanNext: onPlanNext)
                .frame(height: dropZoneHeight)
        }
    }

    private var dayName: String { Formatters.dayName.string(from: day) }
    private var dayNumber: String { Formatters.dayNumber.string(from: day) }
}
