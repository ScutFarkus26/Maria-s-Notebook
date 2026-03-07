// swiftlint:disable file_length
import OSLog
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let logger = Logger.students

// swiftlint:disable:next type_body_length
struct PresentationPill: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) private var calendar
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @SyncedAppStorage("LessonAge.warningDays") private var ageWarningDays: Int = LessonAgeDefaults.warningDays
    @SyncedAppStorage("LessonAge.overdueDays") private var ageOverdueDays: Int = LessonAgeDefaults.overdueDays
    @SyncedAppStorage("LessonAge.freshColorHex") private var ageFreshColorHex: String = LessonAgeDefaults.freshColorHex
    @SyncedAppStorage("LessonAge.warningColorHex")
    private var ageWarningColorHex: String = LessonAgeDefaults.warningColorHex
    @SyncedAppStorage("LessonAge.overdueColorHex")
    private var ageOverdueColorHex: String = LessonAgeDefaults.overdueColorHex

    @AppStorage(UserDefaultsKeys.planningRecentWindowDays) private var recentWindowDays: Int = 1
    @AppStorage(UserDefaultsKeys.lessonsAgendaMissWindow) private var missWindowRaw: String = "all"

    let snapshot: LessonAssignmentSnapshot
    var day: Date?
    var sourceLessonAssignmentID: UUID?
    var targetLessonAssignmentID: UUID?
    var showTimeBadge: Bool = true
    var enableMissHighlight: Bool = false
    var enableMergeDrop: Bool = false
    var showAgeIndicator: Bool = true
    var blockingWork: [UUID: WorkModel] = [:]

    // PERFORMANCE: Accept cached data instead of using @Query per-pill
    var cachedLessons: [Lesson]?
    var cachedStudents: [Student]?

    // Fallback queries only used when cached data isn't provided
    @Query private var lessonsQuery: [Lesson]
    @Query private var studentsQuery: [Student]

    // Use cached data if provided, otherwise fall back to queries
    private var lessons: [Lesson] {
        cachedLessons ?? lessonsQuery
    }
    private var students: [Student] {
        (cachedStudents ?? studentsQuery).uniqueByID
    }

    @State private var showTimeEditor = false
    @State private var isValidDragTarget = false
    @State private var selectedWorkForDetail: WorkModel?
    @State private var isMergeTargeted = false

    // Cached expensive computations to avoid recalculating during scroll
    @State private var cachedAttendanceStatuses: [UUID: AttendanceStatus] = [:]
    @State private var cachedRecentlyPresentedIDs: Set<UUID> = []
    @State private var lastCacheDay: Date?

    private static let timeOnlyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df
    }()

    private var scheduledDate: Date? { snapshot.scheduledFor }

    private var lessonObject: Lesson? { lessons.first(where: { $0.id == snapshot.lessonID }) }

    private var lessonName: String {
        if let name = lessonObject?.name, !name.isEmpty {
            return name
        }
        // Fallback: show lesson ID prefix for debugging
        return "Lesson \(snapshot.lessonID.uuidString.prefix(6))"
    }

    private var subjectColor: Color {
        if let subject = lessonObject?.subject { return AppColors.color(forSubject: subject) }
        return .accentColor
    }

    private var statusesByStudent: [UUID: AttendanceStatus] {
        // Use cached value to avoid database fetch during scroll
        cachedAttendanceStatuses
    }

    private var isAllSelected: Bool {
        let allIDs = Set(students.map { $0.id })
        let groupIDs = Set(snapshot.studentIDs)
        return !allIDs.isEmpty && groupIDs == allIDs
    }

    private var accessibilityLabel: String {
        let studentsText = studentLine
        if studentsText.isEmpty { return lessonName }
        return "\(lessonName), \(studentsText)"
    }

    private var studentLine: String {
        let names = snapshot.studentIDs.compactMap { id -> String? in
            students.first(where: { $0.id == id }).map { displayName(for: $0) } ?? "(Removed)"
        }
        guard !names.isEmpty else {
            let count = snapshot.studentIDs.count
            return count > 0 ? "\(count) student\(count == 1 ? "" : "s")" : ""
        }
        return names.joined(separator: ", ")
    }
    
    /// Synchronous helper that determines if a date is a non-school day using direct ModelContext fetches.
    private func isNonSchoolDaySync(_ date: Date) -> Bool {
        let day = AppCalendar.startOfDay(date)
        let cal = AppCalendar.shared

        // 1) Check explicit non-school day
        if hasNonSchoolDay(for: day) { return true }

        // 2) Check if weekend
        let weekday = cal.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }

        // 3) Check weekend override (makes it a school day)
        return !hasSchoolDayOverride(for: day)
    }

    /// Helper to check if a specific date has a non-school day entry.
    private func hasNonSchoolDay(for day: Date) -> Bool {
        var descriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).isEmpty == false
        } catch {
            logger.warning("Failed to fetch non-school day: \(error)")
            return false
        }
    }

    /// Helper to check if a specific date has a school day override entry.
    private func hasSchoolDayOverride(for day: Date) -> Bool {
        var descriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.date == day })
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).isEmpty == false
        } catch {
            logger.warning("Failed to fetch school day override: \(error)")
            return false
        }
    }
    
    private func recentSchoolDayStarts(anchor: Date, count: Int) -> [Date] {
        var result: [Date] = []
        var cursor = AppCalendar.startOfDay(anchor)
        let needed = max(1, count)
        while result.count < needed {
            if !isNonSchoolDaySync(cursor) {
                result.append(cursor)
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return result.reversed()
    }

    private var recentlyPresentedStudentIDs: Set<UUID> {
        // Use cached value to avoid expensive database fetches during scroll
        cachedRecentlyPresentedIDs
    }

    private func computeRecentlyPresentedStudentIDs(anchor: Date) -> Set<UUID> {
        // Determine the window of recent school days to consider
        let days = recentSchoolDayStarts(anchor: anchor, count: max(1, recentWindowDays))
        guard let start = days.first,
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: (days.last ?? start)) else { return [] }

        let excludedLessonIDs = getExcludedParshaLessonIDs()
        let presented = fetchPresentedLessonAssignments(from: start, to: endExclusive)
        let filtered = presented.filter { !excludedLessonIDs.contains($0.resolvedLessonID) }
        return Set(filtered.flatMap { $0.resolvedStudentIDs })
    }

    /// Helper to get lesson IDs that should be excluded (e.g., Parsha lessons).
    private func getExcludedParshaLessonIDs() -> Set<UUID> {
        let normalized = { (s: String) in s.normalizedForComparison() }
        let parshaLessons = lessons.filter { l in
            let s = normalized(l.subject)
            let g = normalized(l.group)
            return s == "parsha" || g == "parsha"
        }
        return Set(parshaLessons.map { $0.id })
    }

    /// Helper to fetch presented LessonAssignments within a date range.
    private func fetchPresentedLessonAssignments(from start: Date, to endExclusive: Date) -> [LessonAssignment] {
        let presentedRaw = LessonAssignmentState.presented.rawValue
        let predicate = #Predicate<LessonAssignment> {
            $0.stateRaw == presentedRaw &&
            $0.presentedAt.flatMap { $0 >= start && $0 < endExclusive } == true
        }
        do {
            return try modelContext.fetch(FetchDescriptor<LessonAssignment>(predicate: predicate))
        } catch {
            logger.warning("Failed to fetch presented lesson assignments: \(error)")
            return []
        }
    }

    @MainActor
    private func loadRecentlyPresentedIDsShared(for day: Date) -> Set<UUID> {
        let key = RecentPresentationCache.Key(
            day: AppCalendar.startOfDay(day),
            windowDays: max(1, recentWindowDays)
        )
        if let cached = RecentPresentationCache.value(for: key) {
            return cached
        }
        let computed = computeRecentlyPresentedStudentIDs(anchor: day)
        RecentPresentationCache.store(computed, for: key)
        return computed
    }

    private var suppressHighlighting: Bool {
        // When not explicitly enabled, or when the agenda filter is All/0 days, do not highlight any chips
        return !enableMissHighlight || missWindowRaw == "all" || recentWindowDays == 0
    }

    private struct StudentChip {
        let id: UUID
        let label: String
        let isMissing: Bool
        let status: AttendanceStatus?
        let hasHad: Bool
        let blockingWork: WorkModel?
    }
    
    private var studentChips: [StudentChip] {
        var chips: [StudentChip] = []
        for id in snapshot.studentIDs {
            if let s = students.first(where: { $0.id == id }) {
                chips.append(StudentChip(
                    id: id,
                    label: displayName(for: s),
                    isMissing: false,
                    status: statusesByStudent[id],
                    hasHad: recentlyPresentedStudentIDs.contains(id),
                    blockingWork: blockingWork[id]
                ))
            } else {
                chips.append(StudentChip(
                    id: id, label: "(Removed)", isMissing: true,
                    status: nil, hasHad: true, blockingWork: nil
                ))
            }
        }
        return chips
    }

    private func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private var ageSchoolDays: Int {
        snapshot.schoolDaysSinceCreation(asOf: Date(), using: modelContext, calendar: calendar)
    }

    private var ageStatus: LessonAgeStatus {
        if ageSchoolDays >= max(0, ageOverdueDays) { return .overdue }
        if ageSchoolDays >= max(0, ageWarningDays) { return .warning }
        return .fresh
    }

    private var ageColor: Color {
        switch ageStatus {
        case .fresh: return ColorUtils.color(from: ageFreshColorHex)
        case .warning: return ColorUtils.color(from: ageWarningColorHex)
        case .overdue: return ColorUtils.color(from: ageOverdueColorHex)
        }
    }

    private var ageIndicator: some View {
        Rectangle()
            .fill(ageColor)
            .frame(width: UIConstants.ageIndicatorWidth)
            .opacity(snapshot.isGiven ? 0.0 : 1.0)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var studentChipsView: some View {
        if !studentChips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(studentChips, id: \.id) { chip in
                        let isAbsent = (chip.status == .absent)
                        // Removed !isAllSelected check here so that individuals
                        // are highlighted even if the whole group is in the lesson.
                        let highlight = !chip.hasHad && !suppressHighlighting
                        ChipView(
                            label: chip.label,
                            isMissing: chip.isMissing,
                            isAbsent: isAbsent,
                            subjectColor: subjectColor,
                            hasHad: chip.hasHad,
                            suppressIndicator: isAllSelected,
                            highlight: highlight,
                            blockingWork: chip.blockingWork,
                            onTap: {
                                if let c = chip.blockingWork {
                                    selectedWorkForDetail = c
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var mergeHighlightOverlay: some View {
        Group {
            if isMergeTargeted {
                Capsule()
                    .stroke(Color.accentColor.opacity(0.9), lineWidth: 2)
                    .overlay(
                        Text("Merge")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.15))
                            )
                            .padding(6),
                        alignment: .topTrailing
                    )
            }
        }
    }

    @ViewBuilder
    private var timeBadge: some View {
        if showTimeBadge {
            HStack(spacing: 6) {
                if let scheduled = scheduledDate {
                    CanonicalPillButton(
                        isSelected: false,
                        contentFont: .system(.caption2, design: .rounded),
                        horizontalPadding: 6,
                        verticalPadding: 3
                    ) {
                        showTimeEditor = true
                    } content: {
                        Text(Self.timeOnlyFormatter.string(from: scheduled))
                    }
                    #if os(macOS)
                    .popover(isPresented: $showTimeEditor, arrowEdge: .top) {
                        DatePicker("Time", selection: Binding(get: {
                            scheduledDate ?? Date()
                        }, set: { newValue in
                            setTime(newValue)
                        }), displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.field)
                        .padding()
                    }
                    #endif
                }
            }
        }
    }

    private var pillContent: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(subjectColor)
                .frame(width: 6, height: 6)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(lessonName)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                studentChipsView
            }
            .lineSpacing(2)

            Spacer(minLength: 0)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if showAgeIndicator {
                ageIndicator
            }

            pillContent
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .overlay(Capsule().stroke(Color.accentColor.opacity(isValidDragTarget ? 0.45 : 0.0), lineWidth: 2))
            .overlay(mergeHighlightOverlay)
            .overlay(alignment: .trailing) { timeBadge }
            .contentShape(Capsule())
            .accessibilityLabel(accessibilityLabel)
            .onDrop(of: [UTType.text], delegate: PillDropDelegate(
                modelContext: modelContext,
                appRouter: appRouter,
                targetLessonID: snapshot.lessonID,
                targetLessonAssignmentID: targetLessonAssignmentID,
                enableMergeDrop: enableMergeDrop,
                setHighlight: { isValid in isValidDragTarget = isValid },
                setMergeHighlight: { isValid in isMergeTargeted = isValid },
                canAccept: { isValidDragTarget || isMergeTargeted },
                onDidMutate: { reason in saveCoordinator.save(modelContext, reason: reason) }
            ))
        }
        .sheet(item: $selectedWorkForDetail) { work in
            WorkDetailView(workID: work.id) {
                selectedWorkForDetail = nil
            }
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            .presentationSizingFitted()
            #else
            .presentationDetents([.medium, .large])
            #endif
        }
        .task(id: day) {
            // Populate cache once on appear, not during scroll
            let currentDay = day ?? Date()
            guard lastCacheDay == nil
                  || !AppCalendar.shared.isDate(lastCacheDay!, inSameDayAs: currentDay)
            else { return }
            
            // Defer state updates to avoid multiple updates per frame when many pills render simultaneously
            await Task.yield()
            
            lastCacheDay = currentDay
            cachedAttendanceStatuses = modelContext.attendanceStatuses(for: snapshot.studentIDs, on: currentDay)
            cachedRecentlyPresentedIDs = loadRecentlyPresentedIDsShared(for: currentDay)
        }
    }

    private func setTime(_ newTime: Date) {
        guard let id = targetLessonAssignmentID,
              let lessonAssignment = fetchLessonAssignment(by: id) else { return }

        let baseDate = lessonAssignment.scheduledFor ?? snapshot.scheduledFor ?? Date()
        let combined = mergeDateAndTime(date: baseDate, time: newTime)
        lessonAssignment.setScheduledFor(combined, using: calendar)
        saveCoordinator.save(modelContext, reason: "Update lesson time")
    }

    /// Helper to fetch a LessonAssignment by ID.
    private func fetchLessonAssignment(by id: UUID) -> LessonAssignment? {
        var descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            logger.warning("Failed to fetch lesson assignment: \(error)")
            return nil
        }
    }

    /// Helper to merge date components (year, month, day) with time components (hour, minute).
    private func mergeDateAndTime(date: Date, time: Date) -> Date {
        let dayComps = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComps = calendar.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = dayComps.year
        merged.month = dayComps.month
        merged.day = dayComps.day
        merged.hour = timeComps.hour
        merged.minute = timeComps.minute
        return calendar.date(from: merged) ?? time
    }
}
