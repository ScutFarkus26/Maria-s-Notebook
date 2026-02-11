import SwiftUI
import SwiftData

struct DayColumn: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(\.modelContext) private var modelContext

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // OPTIMIZATION: Use shared week studentLessons and filter for this day in memory
    // This avoids making separate database queries for each day
    let weekStudentLessons: [StudentLesson]
    @Query(sort: [SortDescriptor(\Student.lastName), SortDescriptor(\Student.firstName)]) private var allStudentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var allStudents: [Student] {
        TestStudentsFilter.filterVisible(allStudentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    let day: Date
    let availableHeight: CGFloat
    let onSelectLesson: (StudentLesson) -> Void
    let onQuickActions: (StudentLesson) -> Void
    let onPlanNext: (StudentLesson) -> Void

    init(day: Date, weekStudentLessons: [StudentLesson], availableHeight: CGFloat, onSelectLesson: @escaping (StudentLesson) -> Void, onQuickActions: @escaping (StudentLesson) -> Void, onPlanNext: @escaping (StudentLesson) -> Void) {
        self.day = day
        self.weekStudentLessons = weekStudentLessons
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
            var nsDescriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
            nsDescriptor.fetchLimit = 1
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
            var ovDescriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.date == day })
            ovDescriptor.fetchLimit = 1
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
        }
        .padding(.bottom, 12)
    }

    private var dayName: String { Formatters.dayName.string(from: day) }
    private var dayNumber: String { Formatters.dayNumber.string(from: day) }
    
    private var normalizedDay: Date { AppCalendar.startOfDay(day) }
    
    /// OPTIMIZATION: Filter week studentLessons for this specific day in memory
    /// The week data is already loaded with a database-level predicate, so we just filter here
    private var dayStudentLessons: [StudentLesson] {
        let (start, end) = AppCalendar.dayRange(for: normalizedDay)
        return weekStudentLessons.filter { sl in
            // Match either the denormalized day field or the exact scheduled time
            (sl.scheduledForDay >= start && sl.scheduledForDay < end) ||
            (sl.scheduledFor != nil && sl.scheduledFor! >= start && sl.scheduledFor! < end)
        }
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
