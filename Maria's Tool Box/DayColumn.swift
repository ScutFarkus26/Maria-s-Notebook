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

    init(day: Date, availableHeight: CGFloat, onSelectLesson: @escaping (StudentLesson) -> Void, onQuickActions: @escaping (StudentLesson) -> Void, onPlanNext: @escaping (StudentLesson) -> Void) {
        self.day = day
        self.availableHeight = availableHeight
        self.onSelectLesson = onSelectLesson
        self.onQuickActions = onQuickActions
        self.onPlanNext = onPlanNext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            VStack(alignment: .leading, spacing: 0) {
                periodChip(title: "Morning", tint: .blue)
                DropZone(allStudentLessons: studentLessons, day: day, period: PlanningDayPeriod.morning, onSelectLesson: onSelectLesson, onQuickActions: onQuickActions, onPlanNext: onPlanNext)
                    .frame(minHeight: UIConstants.minDropZoneTotalHeight, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)
            }

            periodChip(title: "Afternoon", tint: .orange)
                .padding(.top, UIConstants.dayColumnSpacing)
            DropZone(allStudentLessons: studentLessons, day: day, period: PlanningDayPeriod.afternoon, onSelectLesson: onSelectLesson, onQuickActions: onQuickActions, onPlanNext: onPlanNext)
                .frame(minHeight: UIConstants.minDropZoneTotalHeight, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dayName: String { Formatters.dayName.string(from: day) }
    private var dayNumber: String { Formatters.dayNumber.string(from: day) }
    
    private func periodChip(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(tint.opacity(0.12))
            )
    }
}

