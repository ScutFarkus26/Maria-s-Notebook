import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct StudentLessonPill: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
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
    var blockingContracts: [UUID: WorkContract] = [:]

    @State private var showTimeEditor: Bool = false
    @State private var isValidDragTarget: Bool = false
    @State private var selectedContractForDetail: WorkContract? = nil

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
        guard let day else { return [:] }
        return modelContext.attendanceStatuses(for: snapshot.studentIDs, on: day)
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
        // Determine the window of recent school days to consider
        let anchor = day ?? Date()
        let days = recentSchoolDayStarts(anchor: anchor, count: max(1, recentWindowDays))
        guard let start = days.first,
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: (days.last ?? start)) else { return [] }

        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
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
        let blockingContract: WorkContract?
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
                    blockingContract: blockingContracts[id]
                ))
            } else {
                chips.append(StudentChip(id: id, label: "(Removed)", isMissing: true, status: nil, hasHad: true, blockingContract: nil))
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

    private struct ChipView: View {
        let label: String
        let isMissing: Bool
        let isAbsent: Bool
        let subjectColor: Color
        let hasHad: Bool
        let suppressIndicator: Bool
        let highlight: Bool
        let blockingContract: WorkContract?
        
        var onTap: (() -> Void)? = nil

        var body: some View {
            // If tappable (has blocking contract), wrap in button to capture touch
            if let _ = blockingContract {
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
                if blockingContract != nil {
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
            Rectangle()
                .fill(ageColor)
                .frame(width: UIConstants.ageIndicatorWidth)
                .opacity(snapshot.isGiven ? 0.0 : 1.0)
                .accessibilityHidden(true)

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
                                        blockingContract: chip.blockingContract,
                                        onTap: {
                                            if let c = chip.blockingContract {
                                                selectedContractForDetail = c
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .lineSpacing(2)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .overlay(Capsule().stroke(Color.accentColor.opacity(isValidDragTarget ? 0.45 : 0.0), lineWidth: 2))
            .overlay(alignment: .trailing) {
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
            .contentShape(Capsule())
            .accessibilityLabel(accessibilityLabel)
            .onDrop(of: [UTType.text], delegate: PillDropDelegate(
                modelContext: modelContext,
                appRouter: appRouter,
                targetLessonID: snapshot.lessonID,
                targetStudentLessonID: targetStudentLessonID,
                setHighlight: { isValid in isValidDragTarget = isValid },
                canAccept: { isValidDragTarget },
                onDidMutate: { reason in _ = saveCoordinator.save(modelContext, reason: reason) }
            ))
        }
        .sheet(item: $selectedContractForDetail) { contract in
            WorkContractDetailSheet(contract: contract) {
                selectedContractForDetail = nil
            }
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            .presentationSizingFitted()
            #else
            .presentationDetents([.medium, .large])
            #endif
        }
    }

    private func setTime(_ newTime: Date) {
        guard let id = targetStudentLessonID else { return }
        let desc = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id })
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
        let setHighlight: (Bool) -> Void
        let canAccept: () -> Bool
        let onDidMutate: (String) -> Void

        func dropEntered(info: DropInfo) { checkHighlight(info: info) }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            checkHighlight(info: info)
            return canAccept() ? DropProposal(operation: .copy) : DropProposal(operation: .cancel)
        }

        func dropExited(info: DropInfo) { setHighlight(false) }

        func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.text]) }

        func performDrop(info: DropInfo) -> Bool {
            setHighlight(false)
            guard canAccept() else { return false }
            guard let targetID = targetStudentLessonID else { return false }
            let providers = info.itemProviders(for: [UTType.text])
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let ns = reading as? NSString else { return }
                let str = ns as String
                guard let decoded = DragPayload.decode(str) else { return }
                Task { @MainActor in
                    let sourceID = decoded.sourceID
                    let lessonID = decoded.lessonID
                    let studentID = decoded.studentID
                    let srcDesc = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == sourceID })
                    let tgtDesc = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == targetID })
                    let src = (try? modelContext.fetch(srcDesc))?.first
                    let tgt = (try? modelContext.fetch(tgtDesc))?.first
                    guard let source = src, let target = tgt, source.id != target.id, lessonID == targetLessonID else { return }
                    let studentIDString = studentID.uuidString
                    if !target.studentIDs.contains(studentIDString) {
                        target.studentIDs.append(studentIDString)
                        if !target.students.contains(where: { $0.id == studentID }) {
                            let stuDesc = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
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
                        let fetch = FetchDescriptor<Student>(predicate: #Predicate { remainingIDs.contains($0.id) })
                        let fetched = (try? modelContext.fetch(fetch)) ?? []
                        source.students = fetched
                        // Removed: source.syncSnapshotsFromRelationships()
                    }
                    onDidMutate("Move student between lessons")
                    appRouter.refreshPlanningInbox()
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
                        if lessonID == targetLessonID, sourceID != targetID { setHighlight(true) } else { setHighlight(false) }
                    }
                } else {
                    Task { @MainActor in setHighlight(false) }
                }
            }
        }
    }
}
