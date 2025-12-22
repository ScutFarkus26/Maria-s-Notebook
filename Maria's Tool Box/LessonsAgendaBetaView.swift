import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LessonsAgendaBetaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query private var studentLessons: [StudentLesson]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]

    @AppStorage("PlanningInbox.order") private var inboxOrderRaw: String = ""
    @AppStorage("LessonsAgendaBeta.startDate") private var startDateRaw: Double = 0

    @State private var startDate: Date = Date()
    @State private var selectedStudentLessonForDetail: StudentLesson? = nil

    // Age settings
    @AppStorage("LessonAge.warningDays") private var ageWarningDays: Int = LessonAgeDefaults.warningDays
    @AppStorage("LessonAge.overdueDays") private var ageOverdueDays: Int = LessonAgeDefaults.overdueDays
    @AppStorage("LessonAge.freshColorHex") private var ageFreshHex: String = LessonAgeDefaults.freshColorHex
    @AppStorage("LessonAge.warningColorHex") private var ageWarningHex: String = LessonAgeDefaults.warningColorHex
    @AppStorage("LessonAge.overdueColorHex") private var ageOverdueHex: String = LessonAgeDefaults.overdueColorHex

    private var orderedUnscheduledLessons: [StudentLesson] {
        let base = studentLessons.filter { $0.scheduledFor == nil && !$0.isGiven }
        return InboxOrderStore.orderedUnscheduled(from: base, orderRaw: inboxOrderRaw)
    }

    private func isNonSchool(_ day: Date) -> Bool {
        SchoolCalendar.isNonSchoolDay(day, using: modelContext)
    }

    private var days: [Date] {
        // Compute 14 upcoming school days starting at startDate
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: startDate)
        var safety = 0
        while result.count < 14 && safety < 1000 {
            if !isNonSchool(cursor) { result.append(cursor) }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            safety += 1
        }
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // Top: Inbox (~50% height)
                inboxView
                    .frame(height: proxy.size.height * 0.5)
                Divider()
                // Bottom: Calendar strip (~50% height)
                calendarStrip
                    .frame(height: proxy.size.height * 0.5)
            }
        }
        .onAppear {
            if startDateRaw != 0 {
                startDate = Date(timeIntervalSinceReferenceDate: startDateRaw)
            } else {
                startDate = AgendaSchoolDayRules.computeInitialStartDate(
                    calendar: calendar,
                    isNonSchoolDay: { day in SchoolCalendar.isNonSchoolDay(day, using: modelContext) }
                )
                startDateRaw = startDate.timeIntervalSinceReferenceDate
            }
            syncInboxOrderWithCurrentBase()
        }
        .onChange(of: startDate) { _, new in
            startDateRaw = new.timeIntervalSinceReferenceDate
        }
        .onChange(of: studentLessons.map { $0.id }) { _, _ in
            syncInboxOrderWithCurrentBase()
        }
        .sheet(item: $selectedStudentLessonForDetail) { sl in
            StudentLessonDetailView(studentLesson: sl) {
                selectedStudentLessonForDetail = nil
            }
        #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizing(.fitted)
        #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
        }
    }

    // MARK: - Inbox
    private var inboxView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                Text("Lessons Inbox")
                    .font(.headline)
                Spacer()
                Text("\(orderedUnscheduledLessons.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if orderedUnscheduledLessons.isEmpty {
                VStack { Spacer(); Text("No unscheduled lessons").foregroundStyle(.secondary); Spacer() }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ], alignment: .leading, spacing: 8) {
                        ForEach(orderedUnscheduledLessons, id: \.id) { sl in
                            inboxRow(sl)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func inboxRow(_ sl: StudentLesson) -> some View {
        HStack(spacing: 0) {
            StudentLessonPill(snapshot: sl.snapshot(), day: Date(), targetStudentLessonID: sl.id)
                .onTapGesture { selectedStudentLessonForDetail = sl }
                .onDrag {
                    let provider = NSItemProvider(object: NSString(string: sl.id.uuidString))
                    provider.suggestedName = sl.lesson?.name ?? "Lesson"
                    return provider
                }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Calendar Strip
    private var calendarStrip: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button { moveStart(bySchoolDays: -UIConstants.planningNavigationStepSchoolDays) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                Spacer()
                Button("Today") {
                    startDate = AgendaSchoolDayRules.computeInitialStartDate(calendar: calendar, isNonSchoolDay: { isNonSchool($0) })
                }
                .buttonStyle(.plain)
                Spacer()
                Button { moveStart(bySchoolDays: UIConstants.planningNavigationStepSchoolDays) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(days, id: \.self) { day in
                        BetaDayColumn(day: day, allStudentLessons: studentLessons, onClear: { sl in
                            sl.scheduledFor = nil
                            try? modelContext.save()
                        }, onSelect: { sl in
                            selectedStudentLessonForDetail = sl
                        })
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func moveStart(bySchoolDays delta: Int) {
        guard delta != 0 else { return }
        var remaining = abs(delta)
        var cursor = calendar.startOfDay(for: startDate)
        let step = delta > 0 ? 1 : -1
        while remaining > 0 {
            cursor = calendar.date(byAdding: .day, value: step, to: cursor) ?? cursor
            if !isNonSchool(cursor) { remaining -= 1 }
        }
        startDate = cursor
    }

    // MARK: - Helpers
    private func syncInboxOrderWithCurrentBase() {
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

    private func ageColor(for sl: StudentLesson) -> Color {
        // Hide indicator for given lessons
        if sl.isGiven { return .clear }
        let fresh = ColorUtils.color(from: ageFreshHex)
        let warn = ColorUtils.color(from: ageWarningHex)
        let overdue = ColorUtils.color(from: ageOverdueHex)
        let base = sl.givenAt ?? sl.createdAt
        let days = schoolDaysBetween(from: base, to: Date())
        if days >= ageOverdueDays { return overdue }
        if days >= ageWarningDays { return warn }
        return fresh
    }

    private func schoolDaysBetween(from start: Date, to end: Date) -> Int {
        var count = 0
        var d = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while d < endDay {
            if !SchoolCalendar.isNonSchoolDay(d, using: modelContext) { count += 1 }
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return count
    }

    // MARK: - Nested Day Column
    private struct BetaDayColumn: View {
        @Environment(\.modelContext) private var modelContext
        @Environment(\.calendar) private var calendar

        let day: Date
        let allStudentLessons: [StudentLesson]
        let onClear: (StudentLesson) -> Void
        let onSelect: (StudentLesson) -> Void

        @State private var itemFrames: [UUID: CGRect] = [:]
        @State private var zoneSpaceID = UUID()
        @State private var isTargeted: Bool = false
        @State private var insertionIndex: Int? = nil

        private var scheduledLessonsForDay: [StudentLesson] {
            allStudentLessons.filter { sl in
                guard let scheduled = sl.scheduledFor, !sl.isGiven else { return false }
                return calendar.isDate(scheduled, inSameDayAs: day)
            }
            .sorted { ($0.scheduledFor ?? .distantPast) < ($1.scheduledFor ?? .distantPast) }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Day header
                HStack(spacing: 6) {
                    Text(day.formatted(Date.FormatStyle().weekday(.abbreviated)))
                        .font(.caption.weight(.semibold))
                    Text(day.formatted(Date.FormatStyle().day()))
                        .font(.headline.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 6)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(isTargeted ? 0.08 : 0.04))
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.7), lineWidth: 2)
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            if scheduledLessonsForDay.isEmpty {
                                Text("No plans yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                            } else {
                                ForEach(scheduledLessonsForDay, id: \.id) { sl in
                                    StudentLessonPill(snapshot: sl.snapshot(), day: day, targetStudentLessonID: sl.id, showTimeBadge: false)
                                        .onTapGesture { onSelect(sl) }
                                        .draggable(sl.id.uuidString) {
                                            StudentLessonPill(snapshot: sl.snapshot(), day: day, targetStudentLessonID: sl.id, showTimeBadge: false).opacity(0.85)
                                        }
                                        .contextMenu {
                                            Button("Clear Schedule", systemImage: "xmark.circle") {
                                                onClear(sl)
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
                        .padding(8)
                    }
                }
                .coordinateSpace(name: zoneSpaceID)
                .onPreferenceChange(PillFramePreference.self) { frames in
                    itemFrames = frames
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onDrop(of: [UTType.text], delegate: DayColumnDropDelegate(
                    calendar: calendar,
                    modelContext: modelContext,
                    allStudentLessons: allStudentLessons,
                    day: day,
                    getCurrent: { scheduledLessonsForDay },
                    itemFramesProvider: { itemFrames },
                    onTargetChange: { targeted in
                        withAnimation(.easeInOut(duration: 0.12)) { isTargeted = targeted }
                    },
                    onInsertionIndexChange: { idx in
                        if insertionIndex != idx {
                            withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.85)) { insertionIndex = idx }
                        }
                    }
                ))
                .frame(width: 360)
                .frame(maxHeight: .infinity)
            }
        }

        private struct PillFramePreference: PreferenceKey {
            static var defaultValue: [UUID: CGRect] = [:]
            static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
                value.merge(nextValue(), uniquingKeysWith: { $1 })
            }
        }
    }
}

// MARK: - Drop Delegate for day column
private struct DayColumnDropDelegate: DropDelegate {
    let calendar: Calendar
    let modelContext: ModelContext
    let allStudentLessons: [StudentLesson]
    let day: Date
    let getCurrent: () -> [StudentLesson]
    let itemFramesProvider: () -> [UUID: CGRect]
    let onTargetChange: (Bool) -> Void
    let onInsertionIndexChange: (Int?) -> Void

    func dropEntered(info: DropInfo) {
        onTargetChange(true)
        onInsertionIndexChange(computeIndex(info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onInsertionIndexChange(computeIndex(info))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onTargetChange(false)
        onInsertionIndexChange(nil)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        onTargetChange(false)
        onInsertionIndexChange(nil)
        let providers = info.itemProviders(for: [UTType.text])
        return performDropFromProvidersAsync(providers: providers, location: info.location)
    }

    private func computeIndex(_ info: DropInfo) -> Int? {
        let current = getCurrent()
        let frames = itemFramesProvider()
        let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
            if let rect = frames[item.id] { return (item.id, rect) }
            return nil
        })
        return PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: dict)
    }

    private func performDropFromProvidersAsync(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let payload = (ns as String).trimmingCharacters(in: .whitespacesAndNewlines)
            if let id = UUID(uuidString: payload) {
                Task { @MainActor in
                    applyDrop(of: id, locationY: location.y)
                }
            }
        }
        return true
    }

    @MainActor
    private func applyDrop(of id: UUID, locationY: CGFloat) {
        let current = getCurrent()
        var ids = current.map { $0.id }
        if let existing = ids.firstIndex(of: id) { ids.remove(at: existing) }
        let frames = itemFramesProvider()
        let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
            if let rect = frames[item.id] { return (item.id, rect) }
            return nil
        })
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: locationY, frames: dict)
        let bounded = max(0, min(insertionIndex, ids.count))
        ids.insert(id, at: bounded)
        let baseDate = baseDateForDay(day: day, calendar: calendar)
        let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: baseDate, calendar: calendar, spacingSeconds: 1)
        for id in ids {
            if let item = allStudentLessons.first(where: { $0.id == id }) {
                item.setScheduledFor(timeMap[id], using: AppCalendar.shared)
            }
        }
        try? modelContext.save()
    }

    private func baseDateForDay(day: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: 9, to: startOfDay) ?? startOfDay
    }
}

