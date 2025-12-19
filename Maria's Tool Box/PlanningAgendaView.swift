import SwiftUI
import SwiftData

struct PlanningAgendaView: View {
    @StateObject private var viewModel = PlanningAgendaViewModel()

    // MARK: - Date Format Styles
    private static let dayNameStyle = Date.FormatStyle.dateTime.weekday(.abbreviated)
    private static let dayNumberStyle = Date.FormatStyle.dateTime.day()
    private static let weekStyle = Date.FormatStyle.dateTime.month(.abbreviated).day()

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
    @State private var selectedStudentID: UUID? = nil
    @State private var showStudentFilterPopover: Bool = false
    @State private var filterSelectedIDs: Set<UUID> = []

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
    
    private var filteredStudentLessons: [StudentLesson] {
        if let id = selectedStudentID {
            return studentLessons.filter { $0.resolvedStudentIDs.contains(id) }
        } else {
            return studentLessons
        }
    }

    private var orderedUnscheduledLessonsFiltered: [StudentLesson] {
        if let id = selectedStudentID {
            return orderedUnscheduledLessons.filter { $0.resolvedStudentIDs.contains(id) }
        } else {
            return orderedUnscheduledLessons
        }
    }

    private var inboxOrderChangeToken: String {
        viewModel.unscheduledLessons.map { $0.id.uuidString }.sorted().joined(separator: ",")
    }

    var body: some View {
        UnifiedAgendaView(
            startDate: startDate,
            days: days,
            isNonSchoolDay: { day in viewModel.isNonSchoolDayFast(day) },
            onPrev: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    startDate = AgendaSchoolDayRules.movedStart(bySchoolDays: -7, from: startDate, calendar: calendar, isNonSchoolDay: { viewModel.isNonSchoolDayFast($0) })
                }
            },
            onNext: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    startDate = AgendaSchoolDayRules.movedStart(bySchoolDays: 7, from: startDate, calendar: calendar, isNonSchoolDay: { viewModel.isNonSchoolDayFast($0) })
                }
            },
            onToday: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    startDate = AgendaSchoolDayRules.computeInitialStartDate(calendar: calendar, isNonSchoolDay: { viewModel.isNonSchoolDayFast($0) })
                }
            },
            sidebar: { sidebar },
            headerActions: { headerActions }
        ) { day in
            dayBody(day)
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
            selectedStudentID = nil
            DataMigrations.deduplicateUnpresentedStudentLessons(using: modelContext)
            if startDateRaw == 0 {
                let initial = AgendaSchoolDayRules.computeInitialStartDate(calendar: calendar, isNonSchoolDay: { viewModel.isNonSchoolDayFast($0) })
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
            DataMigrations.deduplicateUnpresentedStudentLessons(using: modelContext)
            viewModel.refreshNow(calendar: calendar, context: modelContext, startDate: startDate)
        }
    }

    private var sidebar: some View {
        InboxSheetView(
            studentLessons: studentLessons,
            orderedUnscheduledLessons: orderedUnscheduledLessonsFiltered,
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
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            // Student filter pill/button
            Button {
                // Initialize single-select set from current selection
                if let id = selectedStudentID { filterSelectedIDs = [id] } else { filterSelectedIDs = [] }
                showStudentFilterPopover = true
            } label: {
                if let id = selectedStudentID, let student = students.first(where: { $0.id == id }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                        Text(StudentFormatter.displayName(for: student))
                            .lineLimit(1)
                        Button {
                            selectedStudentID = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear student filter")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.08))
                    )
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("Filter by Student")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.08))
                    )
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showStudentFilterPopover, arrowEdge: .top) {
                // Enforce single selection by wrapping the binding
                let singleSelectBinding = Binding<Set<UUID>>(
                    get: { filterSelectedIDs },
                    set: { newValue in
                        if newValue.count <= 1 {
                            filterSelectedIDs = newValue
                        } else {
                            if let added = newValue.subtracting(filterSelectedIDs).first {
                                filterSelectedIDs = [added]
                            } else if filterSelectedIDs.subtracting(newValue).first != nil {
                                filterSelectedIDs = []
                            } else {
                                filterSelectedIDs = [newValue.first!]
                            }
                        }
                    }
                )
                StudentPickerPopover(
                    students: students,
                    selectedIDs: singleSelectBinding,
                    onDone: {
                        selectedStudentID = filterSelectedIDs.first
                        showStudentFilterPopover = false
                    }
                )
                .padding(12)
                .frame(minWidth: 320)
            }

            // Existing actions
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
    }

    @ViewBuilder
    private func dayBody(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([DayPeriod.morning, .afternoon], id: \.self) { period in
                AgendaPeriodChipView(period: period)
                    .padding(.bottom, 4)
                AgendaSlot(
                    allStudentLessons: filteredStudentLessons,
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

            // Unplanned students strip (students without any lesson on this day)
            let normalized = AppCalendar.startOfDay(day)
            let unplanned = unplannedStudents(on: normalized)
            if !unplanned.isEmpty {
                UnplannedStudentsStrip(date: normalized, unplanned: unplanned) { student in
                    NotificationCenter.default.post(name: .PlanLessonForStudentOnDate, object: nil, userInfo: [
                        "studentID": student.id,
                        "date": normalized
                    ])
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func dayHeader(_ day: Date) -> some View {
        HStack { // wrapper to preserve exact background and pinned header behavior
            AgendaDaySectionHeaderView(day: day, isNonSchoolDay: viewModel.isNonSchoolDayFast(day))
        }
        .padding(.vertical, 0) // no extra padding beyond internal header view
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

    // MARK: - Unplanned students computation (parity with previous Board view)
    private func plannedStudentIDs(on day: Date) -> Set<UUID> {
        let (start, end) = AppCalendar.dayRange(for: day)
        var acc: [UUID] = []
        for sl in studentLessons {
            guard !sl.isGiven else { continue }
            // Prefer denormalized day if available; fall back to exact scheduled time.
            if sl.scheduledForDay >= start && sl.scheduledForDay < end {
                acc.append(contentsOf: sl.resolvedStudentIDs)
                continue
            }
            if let scheduled = sl.scheduledFor, scheduled >= start && scheduled < end {
                acc.append(contentsOf: sl.resolvedStudentIDs)
            }
        }
        return Set(acc)
    }

    private func unplannedStudents(on day: Date) -> [Student] {
        let planned = plannedStudentIDs(on: day)
        // Filter active students (mirror optional isActive if present)
        let active: [Student] = students.filter { s in
            if let mirror = Mirror(reflecting: s).children.first(where: { $0.label == "isActive" }), let isActive = mirror.value as? Bool {
                return isActive
            }
            return true
        }
        // Respect single-student filter when applied
        if let id = selectedStudentID {
            if let s = active.first(where: { $0.id == id }), !planned.contains(id) {
                return [s]
            } else {
                return []
            }
        }
        return active.filter { !planned.contains($0.id) }
            .sorted { lhs, rhs in
                let ln = lhs.lastName.lowercased()
                let rn = rhs.lastName.lowercased()
                if ln == rn { return lhs.firstName.lowercased() < rhs.firstName.lowercased() }
                return ln < rn
            }
    }
}

#Preview {
    PlanningAgendaView()
        .frame(minWidth: 1000, minHeight: 600)
}
