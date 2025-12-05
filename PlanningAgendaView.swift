import SwiftUI
import SwiftData

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
    
    private var inboxOrderChangeToken: String {
        studentLessons
            .map { sl in
                let scheduledFlag = (sl.scheduledFor != nil) ? 1 : 0
                let givenFlag = sl.isGiven ? 1 : 0
                return "\(sl.id.uuidString)|\(scheduledFlag)|\(givenFlag)"
            }
            .joined(separator: ",")
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
        .onChange(of: inboxOrderChangeToken) { _, _ in
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
                PlanningActions.planNextLesson(for: sl, lessons: lessons, students: students, studentLessons: studentLessons, context: modelContext)
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
            ForEach([DayPeriod.morning, .afternoon], id: \.self) { period in
                Text(period == .morning ? "Morning" : "Afternoon")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                AgendaSlot(
                    allStudentLessons: studentLessons,
                    day: day,
                    period: period,
                    onSelectLesson: { sl in activeSheet = .studentLessonDetail(sl.id) },
                    onQuickActions: { sl in activeSheet = .quickActions(sl.id) },
                    onPlanNext: { sl in PlanningActions.planNextLesson(for: sl, lessons: lessons, students: students, studentLessons: studentLessons, context: modelContext) },
                    onMoveToInbox: { sl in PlanningActions.moveToInbox(sl, context: modelContext) }
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

#Preview {
    PlanningAgendaView()
        .frame(minWidth: 1000, minHeight: 600)
}

