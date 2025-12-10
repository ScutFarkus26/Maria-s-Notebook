import SwiftUI
import SwiftData

struct PlanningAgendaView: View {
    @StateObject private var viewModel = PlanningAgendaViewModel()

    // MARK: - Date Format Styles
    private static let dayNameStyle = Date.FormatStyle.dateTime.weekday(.abbreviated)
    private static let dayNumberStyle = Date.FormatStyle.dateTime.day()
    private static let weekStyle = Date.FormatStyle.dateTime.month(.abbreviated).day()

    // MARK: - Helpers
    private func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    
    private func periodChip(for period: DayPeriod) -> some View {
        let title = (period == .morning ? "Morning" : "Afternoon")
        let tint: Color = (period == .morning ? .blue : .orange)
        return Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(tint.opacity(0.12))
            )
    }

    // MARK: - Environment / Queries
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Query private var studentLessons: [StudentLesson]
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]

    @AppStorage("PlanningInbox.order") private var inboxOrderRaw: String = ""

    // MARK: - State
    @AppStorage("PlanningAgenda.startDate") private var startDateRaw: Double = 0
    @State private var startDate: Date = Date()
    @State private var activeSheet: ActiveSheet? = nil

    private enum ActiveSheet: Identifiable {
        case studentLessonDetail(UUID)
        case quickActions(UUID)
        case giveLessonDraft(UUID)

        var id: String {
            switch self {
            case .studentLessonDetail(let id): return "detail_\(id.uuidString)"
            case .quickActions(let id): return "quick_\(id.uuidString)"
            case .giveLessonDraft(let id): return "giveLessonDraft_\(id.uuidString)"
            }
        }
    }

    private var days: [Date] { viewModel.visibleDays }

    private var orderedUnscheduledLessons: [StudentLesson] {
        InboxOrderStore.orderedUnscheduled(from: viewModel.unscheduledLessons, orderRaw: inboxOrderRaw)
    }
    
    private var inboxOrderChangeToken: String {
        viewModel.unscheduledLessons.map { $0.id.uuidString }.sorted().joined(separator: ",")
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
            let base = viewModel.unscheduledLessons
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
            case .giveLessonDraft(let id):
                StudentLessonDraftSheet(id: id) { activeSheet = nil }
                    #if os(macOS)
                    .frame(minWidth: 720, minHeight: 640)
                    .presentationSizing(.fitted)
                    #else
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
        }
        .task(id: startDate) {
            await viewModel.refresh(calendar: calendar, context: modelContext, startDate: startDate)
        }
        .onChange(of: startDate) { _, new in
            startDateRaw = new.timeIntervalSinceReferenceDate
        }
        .onAppear {
            DataMigrations.deduplicateUnpresentedStudentLessons(using: modelContext)
            if startDateRaw == 0 {
                let initial = computeInitialStartDate()
                startDate = initial
                startDateRaw = initial.timeIntervalSinceReferenceDate
            } else {
                startDate = Date(timeIntervalSinceReferenceDate: startDateRaw)
            }
            Task { await viewModel.refresh(calendar: calendar, context: modelContext, startDate: startDate) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .PlanningInboxNeedsRefresh)) { _ in
            DataMigrations.deduplicateUnpresentedStudentLessons(using: modelContext)
            viewModel.refreshNow(calendar: calendar, context: modelContext, startDate: startDate)
        }
        .onChange(of: studentLessons.map { $0.id }) { _, _ in
            // Keep the inbox in sync with underlying data changes (e.g., deletions)
            DataMigrations.deduplicateUnpresentedStudentLessons(using: modelContext)
            viewModel.refreshNow(calendar: calendar, context: modelContext, startDate: startDate)
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
                PlanningActions.planNextLesson(for: sl, lessons: lessons, students: students, studentLessons: studentLessons, context: modelContext)
            },
            onUpdateOrder: { newOrderRaw in
                inboxOrderRaw = newOrderRaw
                try? modelContext.save()
                // Refresh agenda data so newly created/updated inbox lessons appear immediately
                viewModel.refreshNow(calendar: calendar, context: modelContext, startDate: startDate)
            }
        )
        .frame(width: 280)
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    startDate = movedStart(bySchoolDays: -7)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .accessibilityLabel("Previous week")
            }
            .buttonStyle(.plain)

            Text(weekRangeString)
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    startDate = movedStart(bySchoolDays: 7)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .accessibilityLabel("Next week")
            }
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
                let newSL = StudentLesson(
                    lesson: nil,
                    students: [],
                    createdAt: Date(),
                    scheduledFor: nil,
                    givenAt: nil,
                    isPresented: false,
                    notes: "",
                    needsPractice: false,
                    needsAnotherPresentation: false,
                    followUpWork: ""
                )
                newSL.syncSnapshotsFromRelationships()
                modelContext.insert(newSL)
                try? modelContext.save()
                DispatchQueue.main.async { activeSheet = .giveLessonDraft(newSL.id) }
            } label: {
                Label("Add New", systemImage: "plus.circle.fill")
            }
            .keyboardShortcut("n", modifiers: [])
            .buttonStyle(.plain)

            Menu {
                Button {
                    PlanningActions.pushLessonsWithAbsentStudents(in: days, calendar: calendar, context: modelContext)
                    viewModel.refreshNow(calendar: calendar, context: modelContext, startDate: startDate)
                } label: {
                    Label("Absent → Next Day", systemImage: "person.fill.xmark")
                }
                Button {
                    PlanningActions.pushAllLessonsByOneDay(in: days, calendar: calendar, context: modelContext)
                    viewModel.refreshNow(calendar: calendar, context: modelContext, startDate: startDate)
                } label: {
                    Label("All → +1 Day", systemImage: "calendar.badge.clock")
                }
            } label: {
                Label("Reschedule", systemImage: "arrow.forward.circle")
            }
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
                        .accessibilityLabel("\(dayName(for: day)) \(dayNumber(for: day))")
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
                            Section(header:
                                dayHeader(day)
                                    .background(.bar)
                            ) {
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
        return "\(first.formatted(Self.weekStyle)) - \(last.formatted(Self.weekStyle))"
    }

    private func dayName(for day: Date) -> String {
        day.formatted(Self.dayNameStyle)
    }

    private func dayNumber(for day: Date) -> String {
        day.formatted(Self.dayNumberStyle)
    }

    private func dayID(_ day: Date) -> String {
        let start = calendar.startOfDay(for: day)
        return "day_\(Int(start.timeIntervalSince1970))"
    }

    private func dayShortLabel(for day: Date) -> String {
        day.formatted(Self.dayNameStyle)
    }

    @ViewBuilder
    private func dayHeader(_ day: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(dayName(for: day))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(dayNumber(for: day))
                .font(.system(size: 22, weight: .bold, design: .rounded))
            if viewModel.isNonSchoolDayFast(day) {
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
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func dayBody(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([DayPeriod.morning, .afternoon], id: \.self) { period in
                periodChip(for: period)
                    .padding(.bottom, 4)
                AgendaSlot(
                    allStudentLessons: studentLessons,
                    day: day,
                    period: period,
                    onSelectLesson: { sl in activeSheet = .studentLessonDetail(sl.id) },
                    onQuickActions: { sl in activeSheet = .quickActions(sl.id) },
                    onPlanNext: { sl in PlanningActions.planNextLesson(for: sl, lessons: lessons, students: students, studentLessons: studentLessons, context: modelContext) },
                    onMoveToInbox: { sl in PlanningActions.moveToInbox(sl, context: modelContext) },
                    onMoveStudents: { sl in
                        // Open details; user can tap Move Students…
                        activeSheet = .studentLessonDetail(sl.id)
                    }
                )
                .disabled(viewModel.isNonSchoolDayFast(day))
                .overlay(alignment: .center) {
                    if viewModel.isNonSchoolDayFast(day) {
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
        while viewModel.isNonSchoolDayFast(cursor) {
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return cursor
    }

    private func movedStart(bySchoolDays delta: Int) -> Date {
        guard delta != 0 else { return startOfDay(startDate) }
        var remaining = abs(delta)
        var cursor = calendar.startOfDay(for: startDate)
        let step = delta > 0 ? 1 : -1
        while remaining > 0 {
            cursor = calendar.date(byAdding: .day, value: step, to: cursor) ?? cursor
            if !viewModel.isNonSchoolDayFast(cursor) { remaining -= 1 }
        }
        return cursor
    }

    private func computeInitialStartDate() -> Date {
        let today = calendar.startOfDay(for: Date())
        return firstSchoolDay(onOrAfter: today)
    }
}

#Preview {
    PlanningAgendaView()
        .frame(minWidth: 1000, minHeight: 600)
}

