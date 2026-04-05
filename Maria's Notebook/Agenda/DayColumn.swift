import SwiftUI
import CoreData

struct DayColumn: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(\.managedObjectContext) private var viewContext

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // OPTIMIZATION: Use shared week lesson assignments and filter for this day in memory
    // This avoids making separate database queries for each day
    let weekLessonAssignments: [CDLessonAssignment]
    @FetchRequest(sortDescriptors: CDStudent.sortByLastName)private var allStudentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var allStudents: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(allStudentsRaw).uniqueByID.filter(\.isEnrolled),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    let day: Date
    let availableHeight: CGFloat
    let onSelectLesson: (CDLessonAssignment) -> Void
    let onQuickActions: (CDLessonAssignment) -> Void
    let onPlanNext: (CDLessonAssignment) -> Void

    init(
        day: Date,
        weekLessonAssignments: [CDLessonAssignment],
        availableHeight: CGFloat,
        onSelectLesson: @escaping (CDLessonAssignment) -> Void,
        onQuickActions: @escaping (CDLessonAssignment) -> Void,
        onPlanNext: @escaping (CDLessonAssignment) -> Void
    ) {
        self.day = day
        self.weekLessonAssignments = weekLessonAssignments
        self.availableHeight = availableHeight
        self.onSelectLesson = onSelectLesson
        self.onQuickActions = onQuickActions
        self.onPlanNext = onPlanNext
    }

    /// Synchronous helper that determines if a date is a non-school day using direct NSManagedObjectContext fetches.
    private func isNonSchoolDaySync(_ date: Date) -> Bool {
        let day = AppCalendar.startOfDay(date)
        let cal = AppCalendar.shared

        // 1) Explicit non-school day wins
        do {
            let nsDescriptor = { let r = CDNonSchoolDay.fetchRequest() as! NSFetchRequest<CDNonSchoolDay>; r.predicate = NSPredicate(format: "date == %@", day as CVarArg); r.fetchLimit = 1; return r }()
            let nonSchoolDays: [CDNonSchoolDay] = try viewContext.fetch(nsDescriptor)
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
            let ovDescriptor = { let r = CDSchoolDayOverride.fetchRequest() as! NSFetchRequest<CDSchoolDayOverride>; r.predicate = NSPredicate(format: "date == %@", day as CVarArg); r.fetchLimit = 1; return r }()
            let overrides: [CDSchoolDayOverride] = try viewContext.fetch(ovDescriptor)
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
                    .font(AppTheme.ScaledFont.bodySemibold)
                Text(dayNumber)
                    .font(AppTheme.ScaledFont.header)

                if isNonSchoolDaySync(day) {
                    Text("No School")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(UIConstants.OpacityConstants.accent)))
                        .foregroundStyle(AppColors.destructive)
                }
            }
            .padding(.bottom, 2)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        periodChip(title: "Morning", tint: .blue)
                        DropZone(
                            allLessonAssignments: dayLessonAssignments,
                            day: day,
                            period: PlanningDayPeriod.morning,
                            onSelectLesson: onSelectLesson,
                            onQuickActions: onQuickActions,
                            onPlanNext: onPlanNext
                        )
                            .frame(minHeight: UIConstants.minDropZoneTotalHeight, alignment: .top)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    periodChip(title: "Afternoon", tint: .orange)
                        .padding(.top, UIConstants.dayColumnSpacing)
                    DropZone(
                        allLessonAssignments: dayLessonAssignments,
                        day: day,
                        period: PlanningDayPeriod.afternoon,
                        onSelectLesson: onSelectLesson,
                        onQuickActions: onQuickActions,
                        onPlanNext: onPlanNext
                    )
                        .frame(minHeight: UIConstants.minDropZoneTotalHeight, alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)

                    if !unplannedStudents.isEmpty {
                        UnplannedStudentsStrip(date: normalizedDay, unplanned: unplannedStudents) { student in
                            guard let studentID = student.id else { return }
                            appRouter.requestPlanLessonForStudentOnDate(studentID: studentID, date: normalizedDay)
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

    private var dayName: String { DateFormatters.weekdayAbbrev.string(from: day) }
    private var dayNumber: String { DateFormatters.dayNumber.string(from: day) }

    private var normalizedDay: Date { AppCalendar.startOfDay(day) }

    /// OPTIMIZATION: Filter week lesson assignments for this specific day in memory
    /// The week data is already loaded with a database-level predicate, so we just filter here
    private var dayLessonAssignments: [CDLessonAssignment] {
        let (start, end) = AppCalendar.dayRange(for: normalizedDay)
        return weekLessonAssignments.filter { la in
            // Match either the denormalized day field or the exact scheduled time
            if let day = la.scheduledForDay, day >= start && day < end { return true }
            if let scheduled = la.scheduledFor, scheduled >= start && scheduled < end { return true }
            return false
        }
    }

    private var plannedStudentIDs: Set<UUID> {
        let (start, end) = AppCalendar.dayRange(for: normalizedDay)
        var acc: [UUID] = []
        for la in dayLessonAssignments {
            guard !la.isGiven else { continue }
            // Prefer denormalized day if available; fall back to exact scheduled time.
            if let day = la.scheduledForDay, day >= start && day < end {
                acc.append(contentsOf: la.resolvedStudentIDs)
                continue
            }
            if let scheduled = la.scheduledFor, scheduled >= start && scheduled < end {
                acc.append(contentsOf: la.resolvedStudentIDs)
            }
        }
        return Set(acc)
    }

    private var unplannedStudents: [CDStudent] {
        let planned = plannedStudentIDs
        return allStudents.filter { guard let id = $0.id else { return true }; return !planned.contains(id) }
            .sorted { lhs, rhs in
                let ln = lhs.lastName.lowercased()
                let rn = rhs.lastName.lowercased()
                if ln == rn { return lhs.firstName.lowercased() < rhs.firstName.lowercased() }
                return ln < rn
            }
    }

    private func periodChip(title: String, tint: Color) -> some View {
        Text(title)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(tint.opacity(UIConstants.OpacityConstants.medium))
            )
    }
}
