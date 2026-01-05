import SwiftUI
import SwiftData
@preconcurrency import Combine

struct DayColumn: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(\.modelContext) private var modelContext
    
    // OPTIMIZATION: Load only studentLessons for this day instead of all
    @State private var dayStudentLessons: [StudentLesson] = []
    @Query(sort: [SortDescriptor(\Student.lastName), SortDescriptor(\Student.firstName)]) private var allStudents: [Student]
    
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

    /// Synchronous helper that determines if a date is a non-school day using direct ModelContext fetches.
    private func isNonSchoolDaySync(_ date: Date) -> Bool {
        let day = AppCalendar.startOfDay(date)
        let cal = AppCalendar.shared

        // 1) Explicit non-school day wins
        do {
            let nsDescriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
            let nonSchoolDays: [NonSchoolDay] = try modelContext.fetch(nsDescriptor)
            if !nonSchoolDays.isEmpty { return true }
        } catch {
            // On fetch error, fall back to weekend logic below
        }

        // 2) Weekends are non-school by default (Sunday=1, Saturday=7)
        let weekday = cal.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }

        // 3) Weekend override makes it a school day
        do {
            let ovDescriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.date == day })
            let overrides: [SchoolDayOverride] = try modelContext.fetch(ovDescriptor)
            if !overrides.isEmpty { return false }
        } catch {
            // If override fetch fails, assume weekend remains non-school
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(dayNumber)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                if isNonSchoolDaySync(day) {
                    Text("No School")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(0.15)))
                        .foregroundStyle(.red)
                }
            }
            .padding(.bottom, 2)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        periodChip(title: "Morning", tint: .blue)
                        DropZone(allStudentLessons: dayStudentLessons, day: day, period: PlanningDayPeriod.morning, onSelectLesson: onSelectLesson, onQuickActions: onQuickActions, onPlanNext: onPlanNext)
                            .frame(minHeight: UIConstants.minDropZoneTotalHeight, alignment: .top)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    periodChip(title: "Afternoon", tint: .orange)
                        .padding(.top, UIConstants.dayColumnSpacing)
                    DropZone(allStudentLessons: dayStudentLessons, day: day, period: PlanningDayPeriod.afternoon, onSelectLesson: onSelectLesson, onQuickActions: onQuickActions, onPlanNext: onPlanNext)
                        .frame(minHeight: UIConstants.minDropZoneTotalHeight, alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)

                    if !unplannedStudents.isEmpty {
                        UnplannedStudentsStrip(date: normalizedDay, unplanned: unplannedStudents) { student in
                            appRouter.requestPlanLessonForStudentOnDate(studentID: student.id, date: normalizedDay)
                        }
                        .padding(.top, 8)
                    }

                    // Bottom padding to ensure the strip clears any container clipping
                    Color.clear.frame(height: 12)
                }
            }
        }
        .onAppear {
            AppCalendar.adopt(timeZoneFrom: calendar)
            loadDayStudentLessons()
        }
        .onChange(of: day) { _, _ in
            loadDayStudentLessons()
        }
        .padding(.bottom, 12)
    }

    private var dayName: String { Formatters.dayName.string(from: day) }
    private var dayNumber: String { Formatters.dayNumber.string(from: day) }
    
    private var normalizedDay: Date { AppCalendar.startOfDay(day) }

    /// OPTIMIZATION: Load only studentLessons for this day using predicate
    private func loadDayStudentLessons() {
        let (start, end) = AppCalendar.dayRange(for: normalizedDay)
        
        // Filter by scheduledForDay (denormalized) or scheduledFor for this specific day
        // This significantly reduces memory usage compared to loading all studentLessons
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate<StudentLesson> { sl in
                // Match either the denormalized day field or the exact scheduled time
                (sl.scheduledForDay >= start && sl.scheduledForDay < end) ||
                (sl.scheduledFor != nil && sl.scheduledFor! >= start && sl.scheduledFor! < end)
            }
        )
        dayStudentLessons = modelContext.safeFetch(descriptor)
    }
    
    private var plannedStudentIDs: Set<UUID> {
        let (start, end) = AppCalendar.dayRange(for: normalizedDay)
        var acc: [UUID] = []
        for sl in dayStudentLessons {
            guard !sl.isGiven else { continue }
            // Prefer denormalized day if available; fall back to exact scheduled time.
            if sl.scheduledForDay >= start && sl.scheduledForDay < end {
                acc.append(contentsOf: sl.resolvedStudentIDs)
                continue
            }
            if let scheduled = sl.scheduledFor, scheduled >= start && scheduled < end {
                acc.append(contentsOf: sl.resolvedStudentIDs)
            }
        }
        return Set(acc)
    }

    private var unplannedStudents: [Student] {
        let planned = plannedStudentIDs
        let active: [Student] = allStudents.filter { s in
            // If the model has an isActive flag, use it; otherwise treat all as active.
            if let mirror = Mirror(reflecting: s).children.first(where: { $0.label == "isActive" }), let isActive = mirror.value as? Bool {
                return isActive
            }
            return true
        }
        return active.filter { !planned.contains($0.id) }
            .sorted { lhs, rhs in
                let ln = lhs.lastName.lowercased()
                let rn = rhs.lastName.lowercased()
                if ln == rn { return lhs.firstName.lowercased() < rhs.firstName.lowercased() }
                return ln < rn
            }
    }
    
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

