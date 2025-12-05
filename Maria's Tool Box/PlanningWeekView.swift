import SwiftUI
import SwiftData
import Combine

private enum Formatters {
    static let dayName: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("EEE")
        return df
    }()
    static let dayNumber: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("d")
        return df
    }()
    static let weekRange: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMM d")
        return df
    }()
}

private enum DayPeriod {
    case morning
    case afternoon
}

struct PlanningWeekView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Query private var studentLessons: [StudentLesson]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    @AppStorage("PlanningInbox.order") private var inboxOrderRaw: String = ""
    @State private var startDate: Date = Date()
    @State private var activeSheet: ActiveSheet? = nil

    private enum ActiveSheet: Identifiable {
        case studentLessonDetail(UUID)
        case quickActions(UUID)
        case giveLesson
        case addLesson
        case inbox

        var id: String {
            switch self {
            case .studentLessonDetail(let id): return "detail_\(id.uuidString)"
            case .quickActions(let id): return "quick_\(id.uuidString)"
            case .giveLesson: return "giveLesson"
            case .addLesson: return "addLesson"
            case .inbox: return "inbox"
            }
        }
    }

    private var days: [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: startDate)
        while result.count < 7 {
            if !isNonSchoolDay(cursor) { result.append(cursor) }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return result
    }
    
    private func planNextLesson(for sl: StudentLesson) {
        guard let currentLesson = lessons.first(where: { $0.id == sl.lessonID }) else { return }
        let currentSubject = currentLesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentGroup = currentLesson.group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return }

        let candidates = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentSubject) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }

        guard let idx = candidates.firstIndex(where: { $0.id == currentLesson.id }), idx + 1 < candidates.count else { return }
        let next = candidates[idx + 1]

        let sameStudents = Set(sl.studentIDs)
        let exists = studentLessons.contains { existing in
            existing.lessonID == next.id && Set(existing.studentIDs) == sameStudents && existing.givenAt == nil
        }
        guard !exists else { return }

        let newStudentLesson = StudentLesson(
            id: UUID(),
            lessonID: next.id,
            studentIDs: sl.studentIDs,
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        newStudentLesson.students = students.filter { sameStudents.contains($0.id) }
        newStudentLesson.lesson = lessons.first(where: { $0.id == next.id })
        newStudentLesson.syncSnapshotsFromRelationships()
        modelContext.insert(newStudentLesson)
        try? modelContext.save()
    }
    
    private var orderedUnscheduledLessons: [StudentLesson] {
        InboxOrderStore.orderedUnscheduled(from: studentLessons, orderRaw: inboxOrderRaw)
    }
    
    private var sidebar: some View {
        InboxSheetView(
            studentLessons: studentLessons,
            orderedUnscheduledLessons: orderedUnscheduledLessons,
            inboxOrderRaw: $inboxOrderRaw,
            onOpenDetails: { id in
                activeSheet = .studentLessonDetail(id)
            },
            onQuickActions: { id in
                activeSheet = .quickActions(id)
            },
            onPlanNext: { sl in
                planNextLesson(for: sl)
            },
            onUpdateOrder: { newOrderRaw in
                inboxOrderRaw = newOrderRaw
                try? modelContext.save()
            }
        )
        .frame(width: 280)
    }
    
    var body: some View {
        contentView
            .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .studentLessonDetail(let id):
                if let sl = studentLessons.first(where: { $0.id == id }) {
                    StudentLessonDetailView(studentLesson: sl) {
                        activeSheet = nil
                    }
                } else {
                    EmptyView()
                }
            case .quickActions(let id):
                if let sl = studentLessons.first(where: { $0.id == id }) {
                    StudentLessonQuickActionsView(studentLesson: sl) {
                        activeSheet = nil
                    }
                } else {
                    EmptyView()
                }
            case .giveLesson:
                GiveLessonSheet(
                    lesson: nil,
                    preselectedStudentIDs: [],
                    startGiven: false,
                    allStudents: students,
                    allLessons: lessons
                ) {
                    activeSheet = nil
                }
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizing(.fitted)
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            case .addLesson:
                AddLessonView(defaultSubject: nil, defaultGroup: nil)
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizing(.fitted)
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            case .inbox:
                InboxSheetView(
                    studentLessons: studentLessons,
                    orderedUnscheduledLessons: orderedUnscheduledLessons,
                    inboxOrderRaw: $inboxOrderRaw,
                    onOpenDetails: { id in
                        activeSheet = .studentLessonDetail(id)
                    },
                    onQuickActions: { id in
                        activeSheet = .quickActions(id)
                    },
                    onPlanNext: { sl in
                        planNextLesson(for: sl)
                    },
                    onUpdateOrder: { newOrderRaw in
                        inboxOrderRaw = newOrderRaw
                        try? modelContext.save()
                    }
                )
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizing(.fitted)
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            }
        }
        .onAppear {
            startDate = computeInitialStartDate()
        }
    }
    
    private var contentView: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        WeekGrid(days: days, availableWidth: geometry.size.width - 32, availableHeight: geometry.size.height, onSelectLesson: { sl in activeSheet = .studentLessonDetail(sl.id) }, onQuickActions: { sl in activeSheet = .quickActions(sl.id) }, onPlanNext: { sl in planNextLesson(for: sl) })
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: studentLessons.map { $0.id }) { _, _ in
            let base = studentLessons.filter { $0.scheduledFor == nil && !$0.isGiven }
            let baseIDs = base.map { $0.id }
            var order = InboxOrderStore.parse(inboxOrderRaw).filter { baseIDs.contains($0) }
            let missing = base
                .filter { !order.contains($0.id) }
                .sorted { $0.createdAt < $1.createdAt }
                .map { $0.id }
            order.append(contentsOf: missing)
            inboxOrderRaw = InboxOrderStore.serialize(order)
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    moveStart(bySchoolDays: -7)
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Text(weekRangeString)
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    moveStart(bySchoolDays: 7)
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)

            Spacer()
            
            Button("Today") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    startDate = computeInitialStartDate()
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08), in: Capsule())
            
            Spacer(minLength: 0)
            Button {
                DispatchQueue.main.async {
                    activeSheet = .giveLesson
                }
            } label: {
                Label("Add New", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers
    private var weekRangeString: String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(Formatters.weekRange.string(from: first)) - \(Formatters.weekRange.string(from: last))"
    }

    private func isNonSchoolDay(_ day: Date) -> Bool {
        SchoolCalendar.isNonSchoolDay(day, using: modelContext)
    }

    private func firstSchoolDay(onOrAfter date: Date) -> Date {
        var cursor = calendar.startOfDay(for: date)
        while isNonSchoolDay(cursor) {
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return cursor
    }

    private func moveStart(bySchoolDays delta: Int) {
        guard delta != 0 else { return }
        var remaining = abs(delta)
        var cursor = calendar.startOfDay(for: startDate)
        let step = delta > 0 ? 1 : -1
        while remaining > 0 {
            cursor = calendar.date(byAdding: .day, value: step, to: cursor) ?? cursor
            if !isNonSchoolDay(cursor) { remaining -= 1 }
        }
        startDate = cursor
    }

    private func computeInitialStartDate() -> Date {
        let today = calendar.startOfDay(for: Date())
        let upcomingScheduled = studentLessons.compactMap { sl -> Date? in
            guard let s = sl.scheduledFor, !sl.isGiven else { return nil }
            let d = calendar.startOfDay(for: s)
            return d >= today ? d : nil
        }.sorted().first
        if let upcoming = upcomingScheduled, !isNonSchoolDay(upcoming) {
            return upcoming
        }
        return firstSchoolDay(onOrAfter: today)
    }
}

// MARK: - Week Grid
private struct WeekGrid: View {
    @Environment(\.calendar) private var calendar
    let days: [Date]
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let onSelectLesson: (StudentLesson) -> Void
    let onQuickActions: (StudentLesson) -> Void
    let onPlanNext: (StudentLesson) -> Void

    private var columns: [GridItem] {
        let minWidth: CGFloat = 240
        let maxWidth: CGFloat = 300
        let spacing: CGFloat = 24
        let columnsCount = max(1, days.count)
        let totalSpacing = spacing * CGFloat(columnsCount - 1)
        let contentWidth = max(0, availableWidth - totalSpacing)
        let computed = contentWidth / CGFloat(columnsCount)
        let itemWidth = min(max(computed, minWidth), maxWidth)
        return Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columnsCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(days, id: \.self) { day in
                DayColumn(day: day, availableHeight: availableHeight, onSelectLesson: onSelectLesson, onQuickActions: onQuickActions, onPlanNext: onPlanNext)
            }
        }
    }
}

// MARK: - Day Column
private struct DayColumn: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Query private var studentLessons: [StudentLesson]
    let day: Date
    let availableHeight: CGFloat
    let onSelectLesson: (StudentLesson) -> Void
    let onQuickActions: (StudentLesson) -> Void
    let onPlanNext: (StudentLesson) -> Void

    private var dropZoneHeight: CGFloat {
        // Calculate available height after subtracting header and labels
        // Header ~40, Morning label ~18, Afternoon label ~18, spacing ~14*3 = ~42
        let overhead: CGFloat = 40 + 18 + 18 + 42
        let remaining = max(220, availableHeight - overhead)
        return remaining / 2  // Split between morning and afternoon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Day header
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

            // Morning
            Text("Morning")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            DropZone(allStudentLessons: studentLessons, day: day, period: .morning, onSelectLesson: onSelectLesson, onQuickActions: onQuickActions, onPlanNext: onPlanNext)
                .frame(height: dropZoneHeight)

            // Afternoon
            Text("Afternoon")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            DropZone(allStudentLessons: studentLessons, day: day, period: .afternoon, onSelectLesson: onSelectLesson, onQuickActions: onQuickActions, onPlanNext: onPlanNext)
                .frame(height: dropZoneHeight)
        }
    }

    private var dayName: String {
        Formatters.dayName.string(from: day)
    }

    private var dayNumber: String {
        Formatters.dayNumber.string(from: day)
    }
}

// MARK: - Drop Zone
private struct DropZone: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    let allStudentLessons: [StudentLesson]
    @State private var isTargeted: Bool = false
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var zoneSpaceID = UUID()

    let day: Date
    let period: DayPeriod
    let onSelectLesson: (StudentLesson) -> Void
    let onQuickActions: (StudentLesson) -> Void
    let onPlanNext: (StudentLesson) -> Void

    private var isNonSchool: Bool {
        SchoolCalendar.isNonSchoolDay(day, using: modelContext)
    }

    private var scheduledLessonsForSlot: [StudentLesson] {
        allStudentLessons.filter { sl in
            guard let scheduled = sl.scheduledFor, !sl.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day) && isInSlot(scheduled, period: period)
        }
        .sorted { lhs, rhs in
            (lhs.scheduledFor ?? .distantPast) < (rhs.scheduledFor ?? .distantPast)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .foregroundStyle(Color.primary.opacity(0.25))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .allowsHitTesting(false)

            if isTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 3)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            
            if isNonSchool {
                Text("No School")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                if scheduledLessonsForSlot.isEmpty {
                    Text("Drop lesson here")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scheduledLessonsForSlot, id: \.id) { sl in
                        StudentLessonPill(snapshot: sl.snapshot(), day: Date())
                            .onTapGesture {
                                onSelectLesson(sl)
                            }
                            .contextMenu {
                                Button {
                                    onQuickActions(sl)
                                } label: {
                                    Label("Quick Actions…", systemImage: "bolt")
                                }
                                Button {
                                    onPlanNext(sl)
                                } label: {
                                    Label("Plan Next Lesson in Group", systemImage: "calendar.badge.plus")
                                }
                                Button {
                                    onSelectLesson(sl)
                                } label: {
                                    Label("Open Details", systemImage: "info.circle")
                                }
                            }
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: PillFramePreference.self,
                                        value: [sl.id: proxy.frame(in: .named(zoneSpaceID))]
                                    )
                                }
                            )
                    }
                }
            }
            .padding(12)
        }
        .coordinateSpace(name: zoneSpaceID)
        .onPreferenceChange(PillFramePreference.self) { frames in
            itemFrames = frames
        }
        .contentShape(Rectangle())
        .disabled(isNonSchool)
        .dropDestination(for: String.self, action: { items, location in
            if isNonSchool { return false }
            guard let idString = items.first, let id = UUID(uuidString: idString) else { return false }
            guard let sl = allStudentLessons.first(where: { $0.id == id }) else { return false }
            let current = scheduledLessonsForSlot
            var ids = current.map { $0.id }

            // determine insertion index based on drop location y and frames
            let sortedFrames: [(UUID, CGRect)] = current.compactMap { item in
                if let rect = itemFrames[item.id] {
                    return (item.id, rect)
                }
                return nil
            }
            
            let framesDict = Dictionary(uniqueKeysWithValues: sortedFrames.map { ($0.0, $0.1) })
            let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: framesDict)

            // Remove the moved id if exists
            if let existingIndex = ids.firstIndex(of: sl.id) {
                ids.remove(at: existingIndex)
            }
            // Insert at insertionIndex bounded
            let boundedIndex = max(0, min(insertionIndex, ids.count))
            ids.insert(sl.id, at: boundedIndex)

            let base = dateForSlot(day: day, period: period)
            let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: base, calendar: calendar, spacingSeconds: 1)
            for id in ids {
                if let item = allStudentLessons.first(where: { $0.id == id }) {
                    item.scheduledFor = timeMap[id]
                }
            }

            Task { @MainActor in
                do {
                    try modelContext.save()
                } catch {
                    print("Save error: \(error)")
                    return
                }
            }
            return true
        }, isTargeted: { hovering in
            isTargeted = hovering
        })
    }

    private func isInSlot(_ date: Date, period: DayPeriod) -> Bool {
        let hour = calendar.component(.hour, from: date)
        switch period {
        case .morning:
            return hour < 12
        case .afternoon:
            return hour >= 12
        }
    }

    private func dateForSlot(day: Date, period: DayPeriod) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        let hour: Int
        switch period {
        case .morning:
            hour = 9 // 9 AM for morning
        case .afternoon:
            hour = 14 // 2 PM for afternoon
        }
        return calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
    }

    private struct PillFramePreference: PreferenceKey {
        static var defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }
}

struct StudentLessonPill: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    @Environment(\.calendar) private var calendar
    
    @AppStorage("LessonAge.warningDays") private var ageWarningDays: Int = LessonAgeDefaults.warningDays
    @AppStorage("LessonAge.overdueDays") private var ageOverdueDays: Int = LessonAgeDefaults.overdueDays
    @AppStorage("LessonAge.freshColorHex") private var ageFreshColorHex: String = LessonAgeDefaults.freshColorHex
    @AppStorage("LessonAge.warningColorHex") private var ageWarningColorHex: String = LessonAgeDefaults.warningColorHex
    @AppStorage("LessonAge.overdueColorHex") private var ageOverdueColorHex: String = LessonAgeDefaults.overdueColorHex

    let snapshot: StudentLessonSnapshot
    var day: Date? = nil

    @State private var showTimeEditor: Bool = false

    private static let timeOnlyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df
    }()

    private var scheduledDate: Date? { snapshot.scheduledFor }

    private var lessonObject: Lesson? {
        lessons.first(where: { $0.id == snapshot.lessonID })
    }

    private var lessonName: String {
        lessonObject?.name ?? "Lesson"
    }

    private var subjectColor: Color {
        if let subject = lessonObject?.subject {
            return AppColors.color(forSubject: subject)
        }
        return .accentColor
    }

    private var statusesByStudent: [UUID: AttendanceStatus] {
        guard let day else { return [:] }
        return modelContext.attendanceStatuses(for: snapshot.studentIDs, on: day)
    }

    private var accessibilityLabel: String {
        let studentsText = studentLine
        if studentsText.isEmpty { return lessonName }
        return "\(lessonName), \(studentsText)"
    }

    private var studentLine: String {
        let names: [String] = snapshot.studentIDs.map { id in
            if let s = students.first(where: { $0.id == id }) {
                return displayName(for: s)
            } else {
                return "(Removed)"
            }
        }
        if !names.isEmpty {
            return names.joined(separator: ", ")
        }
        let count = snapshot.studentIDs.count
        return count > 0 ? "\(count) student\(count == 1 ? "" : "s")" : ""
    }
    
    private struct StudentChip { let id: UUID; let label: String; let isMissing: Bool; let status: AttendanceStatus? }
    private var studentChips: [StudentChip] {
        var chips: [StudentChip] = []
        for id in snapshot.studentIDs {
            if let s = students.first(where: { $0.id == id }) {
                chips.append(StudentChip(id: id, label: displayName(for: s), isMissing: false, status: statusesByStudent[id]))
            } else {
                chips.append(StudentChip(id: id, label: "(Removed)", isMissing: true, status: nil))
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

    private var hasConflict: Bool {
        guard day != nil else { return false }
        // naive conflict: if any student is marked absent (already shown) or time overlaps with same-minute another lesson is beyond current pill; we only show a badge if absent or scheduled time exists
        return false
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

    var body: some View {
        HStack(spacing: 0) {
            // Thin age indicator along far left inside the pill card
            Rectangle()
                .fill(ageColor)
                .frame(width: 3)
                .opacity(snapshot.isGiven ? 0.0 : 1.0)
                .accessibilityHidden(true)

            // Existing content preserved
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
                                    Text(chip.label)
                                        .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                                        .foregroundStyle(chip.isMissing ? .secondary : (isAbsent ? .secondary : .primary))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(chip.isMissing ? Color.primary.opacity(0.06) : subjectColor.opacity(isAbsent ? 0.06 : 0.15))
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(isAbsent ? Color.red : Color.clear, lineWidth: 1)
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
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .overlay(alignment: .trailing) {
                HStack(spacing: 6) {
                    if let scheduled = scheduledDate {
                        Button {
                            showTimeEditor = true
                        } label: {
                            Text(Self.timeOnlyFormatter.string(from: scheduled))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        #if os(macOS)
                        .popover(isPresented: $showTimeEditor, arrowEdge: .top) {
                            DatePicker("Time", selection: Binding(get: {
                                scheduledDate ?? Date()
                            }, set: { _ in
                            }), displayedComponents: [.hourAndMinute])
                            .datePickerStyle(.field)
                            .padding()
                        }
                        #endif
                    }

                    if day != nil {
                        let anyAbsent = snapshot.studentIDs.contains { sid in
                            statusesByStudent[sid] == .absent
                        }
                        if anyAbsent {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption2)
                        }
                    }
                }
            }
            .contentShape(Capsule())
        }
    }
}

#Preview {
    PlanningWeekView()
        .frame(minWidth: 1000, minHeight: 600)
}

