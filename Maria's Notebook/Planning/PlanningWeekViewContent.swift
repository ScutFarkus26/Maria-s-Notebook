import SwiftUI
import SwiftData

/// Shared visual component for PlanningWeekView that works with both Mac and iOS data sources.
/// This contains all the UI logic and presentation, but is data-agnostic.
@MainActor
struct PlanningWeekViewContent: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(\.modelContext) private var modelContext
    
    // Data provided by the platform-specific parent view
    let inboxLessons: [StudentLesson]
    let lessons: [Lesson]
    let students: [Student]
    
    @Binding var inboxOrderRaw: String
    @Binding var startDate: Date
    @Binding var activeSheet: PlanningWeekViewContent.ActiveSheet?
    
    // Callback for when data needs to be reloaded (iOS only)
    var onRefreshNeeded: (() -> Void)?
    
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
                EmptyView()
            }
        case .quickActions(let id):
            if let sl = fetchStudentLesson(by: id) {
                StudentLessonQuickActionsView(studentLesson: sl) { activeSheet = nil }
            } else {
                EmptyView()
            }
        case .giveLessonDraft(let id):
            if let sl = fetchStudentLesson(by: id) {
                StudentLessonDetailView(studentLesson: sl, onDone: { activeSheet = nil }, autoFocusLessonPicker: true)
                    .largeSheetSizing()
                    .onDisappear {
                        if let current = fetchStudentLesson(by: id) {
                            if current.lesson == nil && current.studentIDs.isEmpty {
                                modelContext.delete(current)
                                try? modelContext.save()
                                onRefreshNeeded?()
                            }
                        }
                    }
            } else {
                EmptyView()
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
                    try? modelContext.save()
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
        // If not in inbox, fetch from database
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
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
    
    @MainActor private func planNextLesson(for sl: StudentLesson) {
        guard let lessonIDUUID = UUID(uuidString: sl.lessonID),
              let currentLesson = lessons.first(where: { $0.id == lessonIDUUID }) else { return }
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

        // Check for duplicates using a FetchDescriptor
        let nextID = next.id
        let sameStudents = Set(sl.resolvedStudentIDs)
        
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { existing in
                existing.givenAt == nil // Only care if it's active (not given)
            }
        )
        let activeLessons = (try? modelContext.fetch(descriptor)) ?? []
        let exists = activeLessons.contains { existing in
            existing.resolvedLessonID == nextID && Set(existing.resolvedStudentIDs) == sameStudents
        }
        
        guard !exists else { return }

        let newStudentLesson = StudentLesson(
            id: UUID(),
            lessonID: next.id,
            studentIDs: sl.studentIDs.compactMap { UUID(uuidString: $0) },
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
        modelContext.insert(newStudentLesson)
        try? modelContext.save()
        onRefreshNeeded?()
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
                    try? modelContext.save()
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
                        activeSheet = .giveLessonDraft(newSL.id)
                        onRefreshNeeded?()
                    }
                )
                Divider()
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        WeekGrid(days: days, availableWidth: geometry.size.width - (UIConstants.contentHorizontalPadding * 2), availableHeight: geometry.size.height, onSelectLesson: { sl in activeSheet = .studentLessonDetail(sl.id) }, onQuickActions: { sl in activeSheet = .quickActions(sl.id) }, onPlanNext: { sl in planNextLesson(for: sl) })
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
        .onChange(of: inboxLessons.map { $0.id }) { _, _ in
            syncInboxOrderWithCurrentBase()
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
        
        if let nextUp = try? modelContext.fetch(descriptor).first,
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

