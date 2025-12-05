import SwiftUI
import SwiftData

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
    @State private var weekStart: Date = Self.monday(for: Date())
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
        (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
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
                    weekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
                }
            } label: { Image(systemName: "chevron.left") }
            .buttonStyle(.plain)

            Text(weekRangeString)
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                }
            } label: { Image(systemName: "chevron.right") }
            .buttonStyle(.plain)

            Spacer()

            Button("Today") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    weekStart = Self.monday(for: Date(), calendar: calendar)
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08), in: Capsule())

            Button {
                DispatchQueue.main.async { activeSheet = .giveLesson }
            } label: {
                Label("Add New", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Agenda
    private var agenda: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(days, id: \.self) { day in
                    daySection(day)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private func daySection(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Day header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dayName(for: day))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(dayNumber(for: day))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .padding(.bottom, 2)

            // Morning
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

            // Afternoon
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
        guard let end = calendar.date(byAdding: .day, value: 4, to: weekStart) else { return "" }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(fmt.string(from: weekStart)) - \(fmt.string(from: end))"
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

    static func monday(for date: Date, calendar: Calendar = .current) -> Date {
        let cal = calendar
        let startOfDay = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: startOfDay) // 1=Sun, 2=Mon, ...
        let daysToSubtract = (weekday + 5) % 7 // Mon->0, Tue->1, ... Sun->6
        return cal.date(byAdding: .day, value: -daysToSubtract, to: startOfDay) ?? startOfDay
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

            VStack(alignment: .leading, spacing: 8) {
                if scheduledLessonsForSlot.isEmpty {
                    Text("No plans yet")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                } else {
                    ForEach(scheduledLessonsForSlot, id: \.id) { sl in
                        StudentLessonPill(snapshot: sl.snapshot(), day: day)
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
        }
        .coordinateSpace(name: zoneSpaceID)
        .onPreferenceChange(PillFramePreference.self) { frames in
            itemFrames = frames
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .dropDestination(for: String.self, action: { items, location in
            guard let idString = items.first, let id = UUID(uuidString: idString) else { return false }
            guard let sl = allStudentLessons.first(where: { $0.id == id }) else { return false }

            let current = scheduledLessonsForSlot
            var ids = current.map { $0.id }

            // determine insertion index based on drop location y and frames
            let sortedFrames: [(UUID, CGRect)] = current.compactMap { item in
                if let rect = itemFrames[item.id] { return (item.id, rect) }
                return nil
            }

            let insertionIndex: Int = {
                let ordered = sortedFrames.sorted { $0.1.minY < $1.1.minY }
                for (idx, pair) in ordered.enumerated() {
                    let rect = pair.1
                    let midY = rect.midY
                    if location.y < midY { return idx }
                }
                return ordered.count
            }()

            // Remove if it's already in this slot
            if let existingIndex = ids.firstIndex(of: sl.id) { ids.remove(at: existingIndex) }
            // Insert at computed index
            let boundedIndex = max(0, min(insertionIndex, ids.count))
            ids.insert(sl.id, at: boundedIndex)

            // Compute base date for slot and assign sequential times
            let base = dateForSlot(day: day, period: period)
            for (idx, id) in ids.enumerated() {
                if let item = allStudentLessons.first(where: { $0.id == id }) {
                    item.scheduledFor = calendar.date(byAdding: .second, value: idx, to: base)
                }
            }

            Task { @MainActor in
                try? modelContext.save()
            }
            return true
        }, isTargeted: { _ in })
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
