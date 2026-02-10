import SwiftUI
import SwiftData

/// A day column for the Work agenda calendar that displays both work items and student lessons
struct WorkAgendaDayColumn: View {
    @Environment(\.modelContext) private var modelContext
    
    let day: Date
    let availableHeight: CGFloat
    let showPresentations: Bool
    let onPillTap: (WorkPlanItem) -> Void
    let onStudentLessonSelect: ((StudentLesson) -> Void)?
    
    // Fetch work items for this day
    @Query private var allWorkItems: [WorkPlanItem]
    
    // Fetch scheduled student lessons (not yet given)
    @Query(filter: #Predicate<StudentLesson> { !$0.isPresented && $0.givenAt == nil })
    private var allStudentLessons: [StudentLesson]
    
    init(day: Date, availableHeight: CGFloat, showPresentations: Bool = true, onPillTap: @escaping (WorkPlanItem) -> Void, onStudentLessonSelect: ((StudentLesson) -> Void)? = nil) {
        self.day = day
        self.availableHeight = availableHeight
        self.showPresentations = showPresentations
        self.onPillTap = onPillTap
        self.onStudentLessonSelect = onStudentLessonSelect
        
        // Initialize work items query for this day
        let (start, end) = AppCalendar.dayRange(for: day)
        _allWorkItems = Query(filter: #Predicate { $0.scheduledDate >= start && $0.scheduledDate < end })
    }
    
    private var studentLessonsForDay: [StudentLesson] {
        let (start, end) = AppCalendar.dayRange(for: day)
        return allStudentLessons.filter { lesson in
            guard let scheduledDate = lesson.scheduledFor else { return false }
            return scheduledDate >= start && scheduledDate < end
        }
    }
    
    private enum CalendarItem: Identifiable {
        case workPlanItem(WorkPlanItem)
        case studentLesson(StudentLesson)
        
        var id: UUID {
            switch self {
            case .workPlanItem(let wpi): return wpi.id
            case .studentLesson(let sl): return sl.id
            }
        }
        
        var sortDate: Date {
            switch self {
            case .workPlanItem(let wpi): return wpi.scheduledDate
            case .studentLesson(let sl): return sl.scheduledFor ?? .distantPast
            }
        }
    }
    
    private var allItems: [CalendarItem] {
        let work = allWorkItems.map { CalendarItem.workPlanItem($0) }
        let lessons = showPresentations ? studentLessonsForDay.map { CalendarItem.studentLesson($0) } : []
        return (work + lessons).sorted { $0.sortDate < $1.sortDate }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.formatted(Date.FormatStyle().weekday(.abbreviated).day()))
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(allItems) { item in
                    switch item {
                    case .workPlanItem(let wpi):
                        WorkPlanItemPill(item: wpi, isDulled: false) {
                            onPillTap(wpi)
                        }
                        .draggable(UnifiedCalendarDragPayload.workPlanItem(wpi.id).stringRepresentation) {
                            WorkPlanItemPill(item: wpi, isDulled: false)
                                .opacity(0.9)
                        }
                    case .studentLesson(let sl):
                        StudentLessonPill(
                            snapshot: sl.snapshot(),
                            day: day,
                            targetStudentLessonID: sl.id,
                            showTimeBadge: false,
                            enableMergeDrop: false,
                            showAgeIndicator: false
                        )
                        .opacity(0.5)
                        .draggable(UnifiedCalendarDragPayload.studentLesson(sl.id).stringRepresentation) {
                            StudentLessonPill(
                                snapshot: sl.snapshot(),
                                day: day,
                                targetStudentLessonID: sl.id,
                                showTimeBadge: false,
                                enableMergeDrop: false,
                                showAgeIndicator: false
                            )
                            .opacity(0.45)
                        }
                        .onTapGesture {
                            onStudentLessonSelect?(sl)
                        }
                    }
                }
            }
            .padding(8)
            .frame(minWidth: 260, idealWidth: 260, maxWidth: 260, minHeight: 0, idealHeight: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
        }
        .frame(height: availableHeight, alignment: .topLeading)
    }
}
