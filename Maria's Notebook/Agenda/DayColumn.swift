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

    // Pre-filtered to this day's assignments by WeekGrid — no further date filtering needed.
    let lessonAssignments: [CDLessonAssignment]
    @FetchRequest(sortDescriptors: CDStudent.sortByLastName) private var allStudentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var allStudents: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(allStudentsRaw).uniqueByID.filterEnrolled(),
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
        lessonAssignments: [CDLessonAssignment],
        availableHeight: CGFloat,
        onSelectLesson: @escaping (CDLessonAssignment) -> Void,
        onQuickActions: @escaping (CDLessonAssignment) -> Void,
        onPlanNext: @escaping (CDLessonAssignment) -> Void
    ) {
        self.day = day
        self.lessonAssignments = lessonAssignments
        self.availableHeight = availableHeight
        self.onSelectLesson = onSelectLesson
        self.onQuickActions = onQuickActions
        self.onPlanNext = onPlanNext
    }

    @State private var isNonSchool: Bool = false

    /// Reading the version is cheap; the school-day lookup in `.task` runs only
    /// when the day or school-day data changes — not on every render.
    private var schoolDayKey: String { "\(day.timeIntervalSinceReferenceDate)#\(SchoolDayDataVersion.current)" }

    var body: some View {
        // Compute allStudents and planned IDs once per render to avoid evaluating
        // allStudents and lessonAssignments multiple times across DropZones and the strip.
        let students = allStudents
        let plannedIDs = buildPlannedIDs()
        let unplanned = buildUnplanned(students: students, plannedIDs: plannedIDs)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dayName)
                    .font(AppTheme.ScaledFont.bodySemibold)
                Text(dayNumber)
                    .font(AppTheme.ScaledFont.header)

                if isNonSchool {
                    Text("No School")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(UIConstants.OpacityConstants.accent)))
                        .foregroundStyle(AppColors.destructive)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, 2)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        periodChip(title: "Morning", tint: .blue)
                        DropZone(
                            allLessonAssignments: lessonAssignments,
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
                        allLessonAssignments: lessonAssignments,
                        day: day,
                        period: PlanningDayPeriod.afternoon,
                        onSelectLesson: onSelectLesson,
                        onQuickActions: onQuickActions,
                        onPlanNext: onPlanNext
                    )
                        .frame(minHeight: UIConstants.minDropZoneTotalHeight, alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)

                    if !unplanned.isEmpty {
                        UnplannedStudentsStrip(date: normalizedDay, unplanned: unplanned) { student in
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
        .task(id: schoolDayKey) {
            isNonSchool = SchoolCalendarService.shared.isNonSchoolDaySync(day, using: viewContext)
        }
        .padding(.bottom, 12)
    }

    private var dayName: String { DateFormatters.weekdayAbbrev.string(from: day) }
    private var dayNumber: String { DateFormatters.dayNumber.string(from: day) }

    private var normalizedDay: Date { AppCalendar.startOfDay(day) }

    /// IDs of students who already have a non-given assignment scheduled for this day.
    private func buildPlannedIDs() -> Set<UUID> {
        var acc: [UUID] = []
        for la in lessonAssignments where !la.isGiven && la.scheduledFor != nil {
            acc.append(contentsOf: la.resolvedStudentIDs)
        }
        return Set(acc)
    }

    /// Students who have no planned assignment for this day, sorted by last name.
    private func buildUnplanned(students: [CDStudent], plannedIDs: Set<UUID>) -> [CDStudent] {
        students
            .filter { guard let id = $0.id else { return true }; return !plannedIDs.contains(id) }
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
