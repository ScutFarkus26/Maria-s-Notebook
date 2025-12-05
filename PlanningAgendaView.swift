import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum DayPeriod { case morning, afternoon }

struct PlanningAgendaView: View {
    // MARK: - Environment / Queries
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Query private var studentLessons: [StudentLesson]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]

    @AppStorage("PlanningInbox.order") private var inboxOrderRaw: String = ""

    // MARK: - State
    @State private var startDate: Date = Date()
    @State private var activeSheet: ActiveSheet? = nil

    private enum ActiveSheet: Identifiable {
        case studentLessonDetail(UUID)
        case quickActions(UUID)
        case giveLesson

        var id: String {
            switch self {
            case .studentLessonDetail(let id): return "detail_\(id.uuidString)"
            case .quickActions(let id): return "quick_\(id.uuidString)"
            case .giveLesson: return "giveLesson"
            }
        }
    }

    // MARK: - Computed
    private var days: [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: startDate)
        while result.count < 7 {
            if !isNonSchoolDay(cursor) { result.append(cursor) }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return result
    }

    private var orderedUnscheduledLessons: [StudentLesson] {
        InboxOrderStore.orderedUnscheduled(from: studentLessons, orderRaw: inboxOrderRaw)
    }

    private func parseOrder(_ raw: String) -> [UUID] {
        raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    private func serializeOrder(_ ids: [UUID]) -> String {
        ids.map { $0.uuidString }.joined(separator: ",")
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                agenda
            }
        }
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .studentLessonDetail(let id):
                if let sl = studentLessons.first(where: { $0.id == id }) {
                    StudentLessonDetailView(studentLesson: sl) { activeSheet = nil }
                } else { EmptyView() }
            case .quickActions(let id):
                if let sl = studentLessons.first(where: { $0.id == id }) {
                    StudentLessonQuickActionsView(studentLesson: sl) { activeSheet = nil }
                } else { EmptyView() }
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
            }
        }
        .onAppear { startDate = computeInitialStartDate() }
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

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    moveStart(bySchoolDays: -7)
                }
            } label: { Image(systemName: "chevron.left") }
            .buttonStyle(.plain)

            Text(weekRangeString)
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    moveStart(bySchoolDays: 7)
                }
            } label: { Image(systemName: "chevron.right") }
            .buttonStyle(.plain)

            Spacer()

            Button("Today") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    startDate = computeInitialStartDate()
                }
            }
            .keyboardShortcut("t", modifiers: [])
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08), in: Capsule())

            Button {
                DispatchQueue.main.async { activeSheet = .giveLesson }
            } label: {
                Label("Add New", systemImage: "plus.circle.fill")
            }
            .keyboardShortcut("n", modifiers: [])
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Agenda
    private var agenda: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                // Day strip
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        Button(dayShortLabel(for: day)) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                proxy.scrollTo(dayID(day), anchor: .top)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Scrollable agenda with pinned headers
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                        ForEach(days, id: \.self) { day in
                            Section(header: dayHeader(day)) {
                                dayBody(day)
                            }
                            .id(dayID(day))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    // MARK: - Actions
    private func moveToInbox(_ sl: StudentLesson) {
        sl.scheduledFor = nil
        Task { @MainActor in try? modelContext.save() }
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

    // MARK: - Helpers
    private var weekRangeString: String {
        guard let first = days.first, let last = days.last else { return "" }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(fmt.string(from: first)) - \(fmt.string(from: last))"
    }

    private func dayName(for day: Date) -> String {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEE")
        return fmt.string(from: day)
    }

    private func dayNumber(for day: Date) -> String {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("d")
        return fmt.string(from: day)
    }

    private func dayID(_ day: Date) -> String {
        let start = calendar.startOfDay(for: day)
        return "day_\(Int(start.timeIntervalSince1970))"
    }

    private func dayShortLabel(for day: Date) -> String {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEE")
        return fmt.string(from: day)
    }

    @ViewBuilder
    private func dayHeader(_ day: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(dayName(for: day))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(dayNumber(for: day))
                .font(.system(size: 22, weight: .bold, design: .rounded))
            if isNonSchoolDay(day) {
                Text("No School")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red.opacity(0.15)))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(Color.clear)
    }

    @ViewBuilder
    private func dayBody(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Morning")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            AgendaSlot(
                allStudentLessons: studentLessons,
                day: day,
                period: .morning,
                onSelectLesson: { sl in activeSheet = .studentLessonDetail(sl.id) },
                onQuickActions: { sl in activeSheet = .quickActions(sl.id) },
                onPlanNext: { sl in planNextLesson(for: sl) },
                onMoveToInbox: { sl in moveToInbox(sl) }
            )
            .disabled(isNonSchoolDay(day))
            .overlay(alignment: .center) {
                if isNonSchoolDay(day) {
                    Text("No School")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Afternoon")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            AgendaSlot(
                allStudentLessons: studentLessons,
                day: day,
                period: .afternoon,
                onSelectLesson: { sl in activeSheet = .studentLessonDetail(sl.id) },
                onQuickActions: { sl in activeSheet = .quickActions(sl.id) },
                onPlanNext: { sl in planNextLesson(for: sl) },
                onMoveToInbox: { sl in moveToInbox(sl) }
            )
            .disabled(isNonSchoolDay(day))
            .overlay(alignment: .center) {
                if isNonSchoolDay(day) {
                    Text("No School")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
        // Earliest upcoming scheduled day (start-of-day) that is a school day
        let upcomingScheduled = studentLessons.compactMap { sl -> Date? in
            guard let s = sl.scheduledFor, !sl.isGiven else { return nil }
            let d = calendar.startOfDay(for: s)
            return d >= today ? d : nil
        }.sorted().first

        if let upcoming = upcomingScheduled {
            // Prefer the earliest upcoming scheduled day; if it is non-school, fall back to next school day from today
            if !isNonSchoolDay(upcoming) {
                return upcoming
            }
        }
        return firstSchoolDay(onOrAfter: today)
    }
}

// MARK: - Agenda Slot
private struct AgendaSlot: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    let allStudentLessons: [StudentLesson]
    let day: Date
    let period: DayPeriod
    let onSelectLesson: (StudentLesson) -> Void
    let onQuickActions: (StudentLesson) -> Void
    let onPlanNext: (StudentLesson) -> Void
    let onMoveToInbox: (StudentLesson) -> Void

    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var zoneSpaceID = UUID()
    @State private var isTargeted: Bool = false
    @State private var insertionIndex: Int? = nil

    private var scheduledLessonsForSlot: [StudentLesson] {
        allStudentLessons.filter { sl in
            guard let scheduled = sl.scheduledFor, !sl.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day) && isInSlot(scheduled, period: period)
        }
        .sorted { ($0.scheduledFor ?? .distantPast) < ($1.scheduledFor ?? .distantPast) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.02))

            if isTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 3)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 8) {
                if scheduledLessonsForSlot.isEmpty {
                    Text("No plans yet")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                } else {
                    ForEach(Array(scheduledLessonsForSlot.enumerated()), id: \.element.id) { index, sl in
                        StudentLessonPill(snapshot: sl.snapshot(), day: day, sourceStudentLessonID: sl.id, targetStudentLessonID: sl.id)
                            .scaleEffect((isTargeted && insertionIndex == index) ? 1.02 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.9), value: insertionIndex)
                            .onTapGesture { onSelectLesson(sl) }
                            .contextMenu {
                                Button { onQuickActions(sl) } label: { Label("Quick Actions…", systemImage: "bolt") }
                                Button { onPlanNext(sl) } label: { Label("Plan Next Lesson in Group", systemImage: "calendar.badge.plus") }
                                Button { onSelectLesson(sl) } label: { Label("Open Details", systemImage: "info.circle") }
                                Button { onMoveToInbox(sl) } label: { Label("Move to Inbox", systemImage: "tray") }
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
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: scheduledLessonsForSlot.map { $0.id })

            // Draw insertion line
            .overlay(
                GeometryReader { proxy in
                    if let idx = insertionIndex {
                        let frames: [(UUID, CGRect)] = scheduledLessonsForSlot.compactMap { item in
                            if let rect = itemFrames[item.id] { return (item.id, rect) }
                            return nil
                        }.sorted { $0.1.minY < $1.1.minY }
                        if !frames.isEmpty {
                            let y: CGFloat = (idx < frames.count) ? frames[idx].1.minY : (frames.last!.1.maxY)
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                                .position(x: proxy.size.width / 2, y: y)
                                .animation(.easeInOut(duration: 0.12), value: insertionIndex)
                        }
                    }
                }
            )
        }
        .coordinateSpace(name: zoneSpaceID)
        .onPreferenceChange(PillFramePreference.self) { frames in
            itemFrames = frames
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDrop(of: [UTType.text], isTargeted: $isTargeted) { providers, location in
            // Attempt to read text payload
            guard let provider = providers.first else { return false }
            var handled = false
            let semaphore = DispatchSemaphore(value: 0)
            _ = provider.loadObject(ofClass: NSString.self) { reading, _ in
                defer { semaphore.signal() }
                guard let ns = reading as? NSString else { return }
                let payload = ns as String
                if payload.hasPrefix("STUDENT_TO_INBOX:") {
                    // Parse
                    let parts = payload.split(separator: ":")
                    if parts.count == 4,
                       let srcID = UUID(uuidString: String(parts[1])),
                       let lessonID = UUID(uuidString: String(parts[2])),
                       let studentID = UUID(uuidString: String(parts[3])) {
                        // Build current ids
                        let current = scheduledLessonsForSlot
                        var ids = current.map { $0.id }
                        // Determine insertion index using existing frames
                        let frames = itemFrames
                        let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
                            if let rect = frames[item.id] { return (item.id, rect) }
                            return nil
                        })
                        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: dict)
                        // Ensure or create single-student unscheduled StudentLesson for lesson+student
                        let existing = allStudentLessons.first(where: { $0.lessonID == lessonID && $0.scheduledFor == nil && !$0.isGiven && $0.studentIDs == [studentID] })
                        let targetSL: StudentLesson
                        if let ex = existing { targetSL = ex } else {
                            let new = StudentLesson(id: UUID(), lessonID: lessonID, studentIDs: [studentID], createdAt: Date(), scheduledFor: nil, givenAt: nil, notes: "", needsPractice: false, needsAnotherPresentation: false, followUpWork: "")
                            let lessonFetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
                            let studentFetch = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
                            new.lesson = (try? modelContext.fetch(lessonFetch))?.first
                            if let s = (try? modelContext.fetch(studentFetch))?.first { new.students = [s] }
                            new.syncSnapshotsFromRelationships()
                            modelContext.insert(new)
                            targetSL = new
                        }
                        // Insert and assign times
                        ids.removeAll(where: { $0 == targetSL.id })
                        let boundedIndex = max(0, min(insertionIndex, ids.count))
                        ids.insert(targetSL.id, at: boundedIndex)
                        let baseDate = AgendaSlot.baseDateForSlot(day: day, period: period, calendar: calendar)
                        let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: baseDate, calendar: calendar, spacingSeconds: 1)
                        for id in ids {
                            if let item = allStudentLessons.first(where: { $0.id == id }) { item.scheduledFor = timeMap[id] }
                            if id == targetSL.id { targetSL.scheduledFor = timeMap[id] }
                        }
                        // Remove student from source (may be scheduled multi-student)
                        if let src = allStudentLessons.first(where: { $0.id == srcID }) {
                            src.studentIDs.removeAll { $0 == studentID }
                            src.students.removeAll { $0.id == studentID }
                            if src.studentIDs.isEmpty { modelContext.delete(src) } else { src.syncSnapshotsFromRelationships() }
                        }
                        Task { @MainActor in try? modelContext.save() }
                        handled = true
                    }
                }
            }
            semaphore.wait()
            if handled { return true }
            // Fallback to original delegate logic for whole StudentLesson id
            return AgendaSlotDropDelegate(
                calendar: calendar,
                modelContext: modelContext,
                allStudentLessons: allStudentLessons,
                day: day,
                period: period,
                getCurrent: { scheduledLessonsForSlot },
                itemFramesProvider: { itemFrames },
                onTargetChange: { _ in },
                onInsertionIndexChange: { _ in }
            ).performDropFromProviders(providers: providers, location: location)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func isInSlot(_ date: Date, period: DayPeriod) -> Bool {
        let hour = calendar.component(.hour, from: date)
        switch period {
        case .morning: return hour < 12
        case .afternoon: return hour >= 12
        }
    }

    private func dateForSlot(day: Date, period: DayPeriod) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        let hour: Int = (period == .morning) ? 9 : 14
        return calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
    }

    private static func baseDateForSlot(day: Date, period: DayPeriod, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        let hour: Int = (period == .morning) ? 9 : 14
        return calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
    }

    private struct AgendaSlotDropDelegate: DropDelegate {
        let calendar: Calendar
        let modelContext: ModelContext
        let allStudentLessons: [StudentLesson]
        let day: Date
        let period: DayPeriod
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
            return info.hasItemsConforming(to: [UTType.text])
        }

        func performDrop(info: DropInfo) -> Bool {
            onTargetChange(false)
            let providers = info.itemProviders(for: [UTType.text])
            return performDropFromProviders(providers: providers, location: info.location)
        }

        func performDropFromProviders(providers: [NSItemProvider], location: CGPoint) -> Bool {
            guard let provider = providers.first else { return false }
            var result = false
            let semaphore = DispatchSemaphore(value: 0)
            _ = provider.loadObject(ofClass: NSString.self) { reading, _ in
                defer { semaphore.signal() }
                guard let ns = reading as? NSString else { return }
                let payload = ns as String
                if let id = UUID(uuidString: payload.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    // simulate DropInfo path using existing logic
                    var ids = getCurrent().map { $0.id }
                    if let existing = ids.firstIndex(of: id) { ids.remove(at: existing) }
                    // Compute insertion index from location using frames
                    let frames = itemFramesProvider()
                    let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: getCurrent().compactMap { item in
                        if let rect = frames[item.id] { return (item.id, rect) }
                        return nil
                    })
                    let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: dict)
                    let bounded = max(0, min(insertionIndex, ids.count))
                    ids.insert(id, at: bounded)
                    let baseDate = AgendaSlot.baseDateForSlot(day: day, period: period, calendar: calendar)
                    let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: baseDate, calendar: calendar, spacingSeconds: 1)
                    for id in ids { if let item = allStudentLessons.first(where: { $0.id == id }) { item.scheduledFor = timeMap[id] } }
                    Task { @MainActor in try? modelContext.save() }
                    result = true
                }
            }
            semaphore.wait()
            return result
        }

        private func computeIndex(_ info: DropInfo) -> Int {
            let current = getCurrent()
            let frames = itemFramesProvider()
            let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
                if let rect = frames[item.id] { return (item.id, rect) }
                return nil
            })
            return PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: dict)
        }
    }
}

// MARK: - Preference Key
private struct PillFramePreference: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

#Preview {
    PlanningAgendaView()
        .frame(minWidth: 1000, minHeight: 600)
}

