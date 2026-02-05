import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@MainActor
private enum RecentPresentationCache {
    struct Key: Hashable {
        let day: Date
        let windowDays: Int
    }

    private static let maxEntries = 8
    private static var values: [Key: Set<UUID>] = [:]
    private static var order: [Key] = []

    static func value(for key: Key) -> Set<UUID>? {
        values[key]
    }

    static func store(_ value: Set<UUID>, for key: Key) {
        values[key] = value
        if !order.contains(key) { order.append(key) }
        if order.count > maxEntries, let oldest = order.first {
            order.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }
}

struct StudentLessonPill: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @SyncedAppStorage("LessonAge.warningDays") private var ageWarningDays: Int = LessonAgeDefaults.warningDays
    @SyncedAppStorage("LessonAge.overdueDays") private var ageOverdueDays: Int = LessonAgeDefaults.overdueDays
    @SyncedAppStorage("LessonAge.freshColorHex") private var ageFreshColorHex: String = LessonAgeDefaults.freshColorHex
    @SyncedAppStorage("LessonAge.warningColorHex") private var ageWarningColorHex: String = LessonAgeDefaults.warningColorHex
    @SyncedAppStorage("LessonAge.overdueColorHex") private var ageOverdueColorHex: String = LessonAgeDefaults.overdueColorHex

    @AppStorage("Planning.recentWindowDays") private var recentWindowDays: Int = 1
    @AppStorage("LessonsAgenda.missWindow") private var missWindowRaw: String = "all"

    let snapshot: StudentLessonSnapshot
    var day: Date? = nil
    var sourceStudentLessonID: UUID? = nil
    var targetStudentLessonID: UUID? = nil
    var showTimeBadge: Bool = true
    var enableMissHighlight: Bool = false
    var enableMergeDrop: Bool = false
    var showAgeIndicator: Bool = true
    var blockingWork: [UUID: WorkModel] = [:]

    // PERFORMANCE: Accept cached data instead of using @Query per-pill
    var cachedLessons: [Lesson]? = nil
    var cachedStudents: [Student]? = nil

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

    @State private var showTimeEditor: Bool = false
    @State private var isValidDragTarget: Bool = false
    @State private var selectedWorkForDetail: WorkModel? = nil
    @State private var isMergeTargeted: Bool = false

    // Cached expensive computations to avoid recalculating during scroll
    @State private var cachedAttendanceStatuses: [UUID: AttendanceStatus] = [:]
    @State private var cachedRecentlyPresentedIDs: Set<UUID> = []
    @State private var lastCacheDay: Date? = nil

    private static let timeOnlyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df
    }()

    private var scheduledDate: Date? { snapshot.scheduledFor }

    private var lessonObject: Lesson? { lessons.first(where: { $0.id == snapshot.lessonID }) }

    private var lessonName: String { lessonObject?.name ?? "Lesson" }

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
        let names: [String] = snapshot.studentIDs.map { id in
            if let s = students.first(where: { $0.id == id }) { return displayName(for: s) } else { return "(Removed)" }
        }
        if !names.isEmpty { return names.joined(separator: ", ") }
        let count = snapshot.studentIDs.count
        return count > 0 ? "\(count) student\(count == 1 ? "" : "s")" : ""
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

        func norm(_ s: String) -> String { s.normalizedForComparison() }
        let excludedLessonIDs: Set<UUID> = {
            let ids = lessons.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.map { $0.id }
            return Set(ids)
        }()

        // Fetch any presented StudentLesson within the window, regardless of lesson
        let predicate = #Predicate<StudentLesson> {
            $0.isPresented == true &&
            $0.givenAt != nil &&
            $0.givenAt! >= start &&
            $0.givenAt! < endExclusive
        }
        let presented = (try? modelContext.fetch(FetchDescriptor<StudentLesson>(predicate: predicate))) ?? []
        let filtered = presented.filter { !excludedLessonIDs.contains($0.resolvedLessonID) }
        return Set(filtered.flatMap { $0.resolvedStudentIDs })
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
                chips.append(StudentChip(id: id, label: "(Removed)", isMissing: true, status: nil, hasHad: true, blockingWork: nil))
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

    private var ageSchoolDays: Int { snapshot.schoolDaysSinceCreation(asOf: Date(), using: modelContext, calendar: calendar) }

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
                        // Removed !isAllSelected check here so that individuals are highlighted even if the whole group is in the lesson.
                        let highlight = (!chip.hasHad && !suppressHighlighting)
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
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
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

    private struct ChipView: View {
        let label: String
        let isMissing: Bool
        let isAbsent: Bool
        let subjectColor: Color
        let hasHad: Bool
        let suppressIndicator: Bool
        let highlight: Bool
        let blockingWork: WorkModel?
        
        var onTap: (() -> Void)? = nil

        var body: some View {
            // If tappable (has blocking contract), wrap in button to capture touch
            if let _ = blockingWork {
                Button {
                    onTap?()
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        
        @ViewBuilder
        private var content: some View {
            HStack(spacing: 4) {
                if blockingWork != nil {
                    // Minimalist "waiting" indicator
                    Image(systemName: "hourglass")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.orange)
                }
                Text(label)
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
            }
            // Standard text color for readability
            .foregroundStyle(isMissing || isAbsent ? .secondary : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isMissing ? Color.primary.opacity(0.06) : subjectColor.opacity(isAbsent ? 0.06 : 0.15))
            )
            .overlay(
                Capsule().stroke(
                    // Only use red stroke for absence, orange for "missed lesson", clear for blocking (keeps it regular)
                    isAbsent ? Color.red : (highlight ? Color.orange : Color.clear),
                    lineWidth: 1
                )
            )
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
                targetStudentLessonID: targetStudentLessonID,
                enableMergeDrop: enableMergeDrop,
                setHighlight: { isValid in isValidDragTarget = isValid },
                setMergeHighlight: { isValid in isMergeTargeted = isValid },
                canAccept: { isValidDragTarget || isMergeTargeted },
                onDidMutate: { reason in _ = saveCoordinator.save(modelContext, reason: reason) }
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
            guard lastCacheDay == nil || !AppCalendar.shared.isDate(lastCacheDay!, inSameDayAs: currentDay) else { return }
            
            // Defer state updates to avoid multiple updates per frame when many pills render simultaneously
            await Task.yield()
            
            lastCacheDay = currentDay
            cachedAttendanceStatuses = modelContext.attendanceStatuses(for: snapshot.studentIDs, on: currentDay)
            cachedRecentlyPresentedIDs = loadRecentlyPresentedIDsShared(for: currentDay)
        }
    }

    private func setTime(_ newTime: Date) {
        guard let id = targetStudentLessonID else { return }
        var desc = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let sl = (try? modelContext.fetch(desc))?.first else { return }
        let baseDate = sl.scheduledFor ?? snapshot.scheduledFor ?? Date()
        let dayComps = calendar.dateComponents([.year, .month, .day], from: baseDate)
        let timeComps = calendar.dateComponents([.hour, .minute], from: newTime)
        var merged = DateComponents()
        merged.year = dayComps.year
        merged.month = dayComps.month
        merged.day = dayComps.day
        merged.hour = timeComps.hour
        merged.minute = timeComps.minute
        let combined = calendar.date(from: merged) ?? newTime
        sl.setScheduledFor(combined, using: calendar)
        _ = saveCoordinator.save(modelContext, reason: "Update lesson time")
    }

    private struct PillDropDelegate: DropDelegate {
        let modelContext: ModelContext
        let appRouter: AppRouter
        let targetLessonID: UUID
        let targetStudentLessonID: UUID?
        let enableMergeDrop: Bool
        let setHighlight: (Bool) -> Void
        let setMergeHighlight: (Bool) -> Void
        let canAccept: () -> Bool
        let onDidMutate: (String) -> Void

        func dropEntered(info: DropInfo) { checkHighlight(info: info) }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            checkHighlight(info: info)
            return canAccept() ? DropProposal(operation: .copy) : DropProposal(operation: .cancel)
        }

        func dropExited(info: DropInfo) {
            setHighlight(false)
            setMergeHighlight(false)
        }

        func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.text]) }

        func performDrop(info: DropInfo) -> Bool {
            setHighlight(false)
            setMergeHighlight(false)
            guard canAccept() else { return false }
            guard let targetID = targetStudentLessonID else { return false }
            let providers = info.itemProviders(for: [UTType.text])
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let ns = reading as? NSString else { return }
                let str = ns as String
                if let decoded = DragPayload.decode(str) {
                    Task { @MainActor in
                        let sourceID = decoded.sourceID
                        let lessonID = decoded.lessonID
                        let studentID = decoded.studentID
                        var srcDesc = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == sourceID })
                        srcDesc.fetchLimit = 1
                        var tgtDesc = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == targetID })
                        tgtDesc.fetchLimit = 1
                        let src = (try? modelContext.fetch(srcDesc))?.first
                        let tgt = (try? modelContext.fetch(tgtDesc))?.first
                        guard let source = src, let target = tgt, source.id != target.id, lessonID == targetLessonID else { return }
                        let studentIDString = studentID.uuidString
                        if !target.studentIDs.contains(studentIDString) {
                            target.studentIDs.append(studentIDString)
                            if !target.students.contains(where: { $0.id == studentID }) {
                                var stuDesc = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
                                stuDesc.fetchLimit = 1
                                if let s = (try? modelContext.fetch(stuDesc))?.first {
                                    target.students.append(s)
                                } else if let s2 = source.students.first(where: { $0.id == studentID }) {
                                    target.students.append(s2)
                                }
                            }
                            // Removed: target.syncSnapshotsFromRelationships()
                        }
                        source.studentIDs.removeAll { $0 == studentIDString }
                        if source.studentIDs.isEmpty {
                            modelContext.delete(source)
                        } else {
                            let remainingIDs = source.studentIDs.compactMap { UUID(uuidString: $0) }
                            // NOTE: SwiftData #Predicate doesn't support capturing local Array/Set variables,
                            // so we fetch all and filter in memory
                            let remainingSet = Set(remainingIDs)
                            let allStudents = (try? modelContext.fetch(FetchDescriptor<Student>())) ?? []
                            let fetched = allStudents.filter { remainingSet.contains($0.id) }
                            source.students = fetched
                            // Removed: source.syncSnapshotsFromRelationships()
                        }
                        onDidMutate("Move student between lessons")
                        appRouter.refreshPlanningInbox()
                    }
                    return
                }

                if enableMergeDrop, let sourceID = UUID(uuidString: str.trimmed()) {
                    Task { @MainActor in
                        _ = StudentLessonMergeService.merge(
                            sourceID: sourceID,
                            targetID: targetID,
                            context: modelContext
                        )
                    }
                }
            }
            return true
        }

        private func checkHighlight(info: DropInfo) {
            guard let targetID = targetStudentLessonID else { setHighlight(false); return }
            let providers = info.itemProviders(for: [UTType.text])
            guard let provider = providers.first else { setHighlight(false); return }
            provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let ns = reading as? NSString else { Task { @MainActor in setHighlight(false) }; return }
                let str = ns as String
                if let decoded = DragPayload.decode(str) {
                    let sourceID = decoded.sourceID
                    let lessonID = decoded.lessonID
                    Task { @MainActor in
                        if lessonID == targetLessonID, sourceID != targetID {
                            setHighlight(true)
                            setMergeHighlight(false)
                        } else {
                            setHighlight(false)
                            setMergeHighlight(false)
                        }
                    }
                } else if enableMergeDrop, let sourceID = UUID(uuidString: str.trimmed()) {
                    Task { @MainActor in
                        guard sourceID != targetID else {
                            setHighlight(false)
                            setMergeHighlight(false)
                            return
                        }
                        var srcDesc = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == sourceID })
                        srcDesc.fetchLimit = 1
                        let source = (try? modelContext.fetch(srcDesc))?.first
                        if let source, source.resolvedLessonID == targetLessonID, !source.isGiven {
                            setHighlight(false)
                            setMergeHighlight(true)
                        } else {
                            setHighlight(false)
                            setMergeHighlight(false)
                        }
                    }
                } else {
                    Task { @MainActor in
                        setHighlight(false)
                        setMergeHighlight(false)
                    }
                }
            }
        }
    }
}
