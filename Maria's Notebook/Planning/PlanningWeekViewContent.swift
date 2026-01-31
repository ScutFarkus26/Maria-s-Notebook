import SwiftUI
import SwiftData

/// Shared visual component for PlanningWeekView that works with both Mac and iOS data sources.
/// This contains all the UI logic and presentation, but is data-agnostic.
@MainActor
struct PlanningWeekViewContent: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    private var studentLessonRepository: StudentLessonRepository {
        StudentLessonRepository(context: modelContext, saveCoordinator: saveCoordinator)
    }

    // Data provided by the platform-specific parent view
    let inboxLessons: [StudentLesson]
    let lessons: [Lesson]
    let students: [Student]
    
    @Binding var inboxOrderRaw: String
    @Binding var startDate: Date
    @Binding var activeSheet: PlanningWeekViewContent.ActiveSheet?
    
    // Callback for when data needs to be reloaded (iOS only)
    var onRefreshNeeded: (() -> Void)?
    
    // OPTIMIZATION: Load studentLessons for the entire week at once using database-level predicate
    // This avoids 7 separate per-day queries and significantly reduces memory usage
    @State private var weekStudentLessons: [StudentLesson] = []
    
    enum ActiveSheet: Identifiable {
        case studentLessonDetail(UUID)
        case quickActions(UUID)
        case giveLessonDraft(UUID)
        case addLesson
        case inbox

        var id: String {
            switch self {
            case .studentLessonDetail(let id): return "detail_\(id.uuidString)"
            case .quickActions(let id): return "quick_\(id.uuidString)"
            case .giveLessonDraft(let id): return "giveLessonDraft_\(id.uuidString)"
            case .addLesson: return "addLesson"
            case .inbox: return "inbox"
            }
        }
    }
    
    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .studentLessonDetail(let id):
            if let sl = fetchStudentLesson(by: id) {
                StudentLessonDetailView(studentLesson: sl) { activeSheet = nil }
            } else {
                // Keep the sheet alive instead of returning EmptyView to avoid ViewBridge cancellation
                ProgressView("Loading…")
                    .frame(minWidth: 320, minHeight: 240)
                    .task {
                        // Dismiss if the item is no longer available
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        if case .studentLessonDetail(let currentId) = activeSheet, currentId == id {
                            activeSheet = nil
                        }
                    }
            }
        case .quickActions(let id):
            if let sl = fetchStudentLesson(by: id) {
                StudentLessonQuickActionsView(studentLesson: sl) { activeSheet = nil }
            } else {
                // Keep the sheet alive instead of returning EmptyView to avoid ViewBridge cancellation
                ProgressView("Loading…")
                    .frame(minWidth: 320, minHeight: 240)
                    .task {
                        // Dismiss if the item is no longer available
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        if case .quickActions(let currentId) = activeSheet, currentId == id {
                            activeSheet = nil
                        }
                    }
            }
        case .giveLessonDraft(let id):
            if let sl = fetchStudentLesson(by: id) {
                StudentLessonDetailView(studentLesson: sl, onDone: { activeSheet = nil }, autoFocusLessonPicker: true)
                    .largeSheetSizing()
                    .onDisappear {
                        if let current = fetchStudentLesson(by: id) {
                            if current.lesson == nil && current.studentIDs.isEmpty {
                                try? studentLessonRepository.deleteStudentLesson(id: current.id)
                                onRefreshNeeded?()
                            }
                        }
                    }
            } else {
                // Keep the sheet alive instead of returning EmptyView to avoid ViewBridge cancellation
                ProgressView("Preparing…")
                    .frame(minWidth: 320, minHeight: 240)
                    .task {
                        // Dismiss if the draft is no longer available
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        if case .giveLessonDraft(let currentId) = activeSheet, currentId == id {
                            activeSheet = nil
                        }
                    }
            }
        case .addLesson:
            AddLessonView(defaultSubject: nil, defaultGroup: nil)
                .largeSheetSizing()
                .onDisappear {
                    onRefreshNeeded?()
                }
        case .inbox:
            InboxViewContent(
                studentLessons: inboxLessons,
                orderedUnscheduledLessons: orderedUnscheduledLessons,
                inboxOrderRaw: $inboxOrderRaw,
                onOpenDetails: { id in activeSheet = .studentLessonDetail(id) },
                onQuickActions: { id in activeSheet = .quickActions(id) },
                onPlanNext: { sl in planNextLesson(for: sl) },
                onUpdateOrder: { newOrderRaw in
                    inboxOrderRaw = newOrderRaw
                    saveCoordinator.save(modelContext, reason: "Updating inbox order")
                    onRefreshNeeded?()
                }
            )
            .largeSheetSizing()
        }
    }
    
    // Helper to fetch a specific lesson by ID on-demand
    private func fetchStudentLesson(by id: UUID) -> StudentLesson? {
        // First check inboxLessons (common case)
        if let found = inboxLessons.first(where: { $0.id == id }) {
            return found
        }
        // If not in inbox, fetch from database via repository
        return studentLessonRepository.fetchStudentLesson(id: id)
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
    
    /// OPTIMIZATION: Load studentLessons for the entire week using database-level predicate
    /// This fetches all lessons scheduled within the week's date range in a single query
    /// instead of making 7 separate per-day queries, significantly reducing memory usage
    private func loadWeekStudentLessons() {
        guard let firstDay = days.first, let lastDay = days.last else {
            weekStudentLessons = []
            return
        }
        
        // Calculate week range: from start of first day to end of last day
        let weekStart = AppCalendar.startOfDay(firstDay)
        let weekEnd = calendar.date(byAdding: .day, value: 1, to: AppCalendar.startOfDay(lastDay)) ?? weekStart
        
        // Fetch studentLessons scheduled within the week range using database-level predicate
        // Use scheduledForDay (denormalized) for efficient querying, with fallback to scheduledFor
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate<StudentLesson> { sl in
                // Match if scheduledForDay is within week range (most efficient)
                (sl.scheduledForDay >= weekStart && sl.scheduledForDay < weekEnd) ||
                // Or if scheduledFor is within week range (fallback for edge cases)
                (sl.scheduledFor != nil && sl.scheduledFor! >= weekStart && sl.scheduledFor! < weekEnd)
            },
            sortBy: [
                SortDescriptor(\.scheduledFor, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ]
        )
        weekStudentLessons = (try? modelContext.fetch(descriptor)) ?? []
    }
    
    @MainActor private func planNextLesson(for sl: StudentLesson) {
        // Fetch existing StudentLessons for duplicate checking
        let existingStudentLessons = studentLessonRepository.fetchActiveStudentLessons()

        let result = PlanNextLessonService.planNextLesson(
            for: sl,
            allLessons: lessons,
            allStudents: students,
            existingStudentLessons: existingStudentLessons,
            context: modelContext
        )

        if case .success = result {
            studentLessonRepository.save(reason: "Planning next lesson")
            onRefreshNeeded?()
        }
    }
    
    private var orderedUnscheduledLessons: [StudentLesson] {
        InboxOrderStore.orderedUnscheduled(from: inboxLessons, orderRaw: inboxOrderRaw)
    }
    
    private var sidebar: some View {
        PlanningSidebarView {
            InboxViewContent(
                studentLessons: inboxLessons,
                orderedUnscheduledLessons: orderedUnscheduledLessons,
                inboxOrderRaw: $inboxOrderRaw,
                onOpenDetails: { id in activeSheet = .studentLessonDetail(id) },
                onQuickActions: { id in activeSheet = .quickActions(id) },
                onPlanNext: { sl in planNextLesson(for: sl) },
                onUpdateOrder: { newOrderRaw in
                    inboxOrderRaw = newOrderRaw
                    saveCoordinator.save(modelContext, reason: "Updating inbox order")
                    onRefreshNeeded?()
                }
            )
        }
    }
    
    var body: some View {
        contentView
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
            }
    }
    
    private var contentView: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                PlanningHeaderView(
                    weekRange: weekRangeString,
                    onPrevWeek: { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { moveStart(bySchoolDays: -7) } },
                    onNextWeek: { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { moveStart(bySchoolDays: 7) } },
                    onToday: { 
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { 
                            computeInitialStartDate()
                        }
                    },
                    onAddNew: {
                        let newSL = studentLessonRepository.createUnscheduled(
                            lessonID: UUID(),
                            studentIDs: [],
                            lesson: nil,
                            students: []
                        )
                        studentLessonRepository.save(reason: "Creating new presentation")
                        activeSheet = .giveLessonDraft(newSL.id)
                        onRefreshNeeded?()
                    }
                )
                Divider()
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        WeekGrid(
                            days: days,
                            weekStudentLessons: weekStudentLessons,
                            availableWidth: geometry.size.width - (UIConstants.contentHorizontalPadding * 2),
                            availableHeight: geometry.size.height,
                            onSelectLesson: { sl in activeSheet = .studentLessonDetail(sl.id) },
                            onQuickActions: { sl in activeSheet = .quickActions(sl.id) },
                            onPlanNext: { sl in planNextLesson(for: sl) }
                        )
                        .padding(.horizontal, UIConstants.contentHorizontalPadding)
                        .padding(.vertical, UIConstants.contentVerticalPadding)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                Menu {
                    Button {
                        Task {
                            await PlanningActions.pushLessonsWithAbsentStudents(in: days, calendar: calendar, context: modelContext)
                            onRefreshNeeded?()
                        }
                    } label: {
                        Label("Absent → Next Day", systemImage: "person.fill.xmark")
                    }
                    Button {
                        Task {
                            await PlanningActions.pushAllLessonsByOneDay(in: days, calendar: calendar, context: modelContext)
                            onRefreshNeeded?()
                        }
                    } label: {
                        Label("All → +1 Day", systemImage: "calendar.badge.clock")
                    }
                } label: {
                    Label("Reschedule", systemImage: "arrow.forward.circle")
                }
                .buttonStyle(.plain)
                .padding(.trailing, UIConstants.contentHorizontalPadding)
                .padding(.top, UIConstants.headerVerticalPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadWeekStudentLessons()
        }
        .onChange(of: startDate) { _, _ in
            loadWeekStudentLessons()
        }
        .onChange(of: inboxLessons.map { $0.id }) { _, _ in
            syncInboxOrderWithCurrentBase()
        }
        .onChange(of: appRouter.planningInboxRefreshTrigger) { _, _ in
            // Reload week data when external changes occur (e.g., lessons scheduled/unscheduled)
            loadWeekStudentLessons()
        }
    }

    // MARK: - Helpers
    private var weekRangeString: String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(Formatters.weekRange.string(from: first)) - \(Formatters.weekRange.string(from: last))"
    }

    /// Synchronous helper that determines if a date is a non-school day using direct ModelContext fetches.
    /// Rules:
    /// - Explicit NonSchoolDay records mark weekdays as non-school
    /// - Weekends are non-school by default unless a SchoolDayOverride exists for that date
    private func isNonSchoolDay(_ day: Date) -> Bool {
        let day = calendar.startOfDay(for: day)

        // 1) Explicit non-school day wins
        do {
            let nsDescriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
            let nonSchoolDays: [NonSchoolDay] = try modelContext.fetch(nsDescriptor)
            if !nonSchoolDays.isEmpty { return true }
        } catch {
            // On fetch error, fall back to weekend logic below
        }

        // 2) Weekends are non-school by default (Sunday=1, Saturday=7)
        let weekday = calendar.component(.weekday, from: day)
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

    // One-time fetch to find the start date
    private func computeInitialStartDate() {
        let today = calendar.startOfDay(for: Date())
        
        // Fetch only future scheduled lessons to find the next one
        var descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.scheduledFor != nil && $0.isGiven == false },
            sortBy: [SortDescriptor(\.scheduledFor)]
        )
        descriptor.fetchLimit = 1 // We only need the very first one
        
        if let nextUp = modelContext.safeFetchFirst(descriptor),
           let date = nextUp.scheduledFor {
            let start = calendar.startOfDay(for: date)
            if start >= today && !isNonSchoolDay(start) {
                self.startDate = start
                return
            }
        }
        
        // Fallback
        self.startDate = firstSchoolDay(onOrAfter: today)
    }

    @MainActor
    private func syncInboxOrderWithCurrentBase() {
        let baseIDs = inboxLessons.map { $0.id }
        var order = InboxOrderStore.parse(inboxOrderRaw).filter { baseIDs.contains($0) }
        let missing = inboxLessons
            .filter { !order.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.id }
        order.append(contentsOf: missing)
        inboxOrderRaw = InboxOrderStore.serialize(order)
    }
}

