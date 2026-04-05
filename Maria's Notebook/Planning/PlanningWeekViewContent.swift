import SwiftUI
import OSLog
import CoreData

/// Shared visual component for PlanningWeekView that works with both Mac and iOS data sources.
/// This contains all the UI logic and presentation, but is data-agnostic.
@MainActor
// swiftlint:disable:next type_body_length
struct PlanningWeekViewContent: View {
    private static let logger = Logger.planning
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(SaveCoordinator.self) var saveCoordinator

    var presentationRepository: PresentationRepository {
        PresentationRepository(context: managedObjectContext, saveCoordinator: saveCoordinator)
    }

    // Data provided by the platform-specific parent view
    let inboxLessons: [CDLessonAssignment]
    let lessons: [CDLesson]
    let students: [CDStudent]
    
    private var inboxLessonIDs: [UUID] {
        inboxLessons.compactMap(\.id)
    }
    
    @Binding var inboxOrderRaw: String
    @Binding var startDate: Date
    @Binding var activeSheet: PlanningWeekViewContent.ActiveSheet?
    
    // Callback for when data needs to be reloaded (iOS only)
    var onRefreshNeeded: (() -> Void)?
    
    // OPTIMIZATION: Load lesson assignments for the entire week at once using database-level predicate
    // This avoids 7 separate per-day queries and significantly reduces memory usage
    @State private var weekLessonAssignments: [CDLessonAssignment] = []
    
    private var days: [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: startDate)
        while result.count < 7 {
            if !isNonSchoolDay(cursor) { result.append(cursor) }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return result
    }
    
    /// OPTIMIZATION: Load lesson assignments for the entire week using database-level predicate
    /// This fetches all lessons scheduled within the week's date range in a single query
    private func loadWeekLessonAssignments() {
        guard let firstDay = days.first, let lastDay = days.last else {
            weekLessonAssignments = []
            return
        }

        let weekStart = AppCalendar.startOfDay(firstDay)
        let weekEnd = calendar.date(byAdding: .day, value: 1, to: AppCalendar.startOfDay(lastDay)) ?? weekStart
        let presentedRaw = LessonAssignmentState.presented.rawValue

        let descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(
            format: "stateRaw != %@ AND ((scheduledForDay >= %@ AND scheduledForDay < %@) OR (scheduledFor >= %@ AND scheduledFor < %@))",
            presentedRaw, weekStart as CVarArg, weekEnd as CVarArg, weekStart as CVarArg, weekEnd as CVarArg
        )
        descriptor.sortDescriptors = [
                NSSortDescriptor(key: "scheduledForDay", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]
        do {
            weekLessonAssignments = try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch week lesson assignments: \(error, privacy: .public)")
            weekLessonAssignments = []
        }
    }
    
    @MainActor func planNextLesson(for la: CDLessonAssignment) {
        // Fetch existing LessonAssignments via SwiftData (PlanNextLessonService expects SwiftData types)
        let presentedRaw = LessonAssignmentState.presented.rawValue
        let fetch: NSFetchRequest<CDLessonAssignment> = {
            let r = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
            r.predicate = NSPredicate(format: "stateRaw != %@", presentedRaw)
            return r
        }()
        let existingLessonAssignments = (try? viewContext.fetch(fetch)) ?? []

        let result = PlanNextLessonService.planNextLesson(
            for: la,
            allLessons: lessons,
            allStudents: students,
            existingLessonAssignments: existingLessonAssignments,
            context: viewContext
        )

        if case .success = result {
            presentationRepository.save(reason: "Planning next lesson")
            onRefreshNeeded?()
        }
    }
    
    var orderedUnscheduledLessons: [CDLessonAssignment] {
        InboxOrderStore.orderedUnscheduled(from: inboxLessons, orderRaw: inboxOrderRaw)
    }
    
    private var sidebar: some View {
        PlanningSidebarView {
            InboxViewContent(
                lessonAssignments: inboxLessons,
                orderedUnscheduledLessons: orderedUnscheduledLessons,
                inboxOrderRaw: $inboxOrderRaw,
                onOpenDetails: { id in activeSheet = .presentationDetail(id) },
                onQuickActions: { id in activeSheet = .quickActions(id) },
                onPlanNext: { la in planNextLesson(for: la) },
                onUpdateOrder: { newOrderRaw in
                    inboxOrderRaw = newOrderRaw
                    saveCoordinator.save(viewContext, reason: "Updating inbox order")
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
                    onPrevWeek: handlePrevWeek,
                    onNextWeek: handleNextWeek,
                    onToday: handleToday,
                    onAddNew: handleAddNew,
                    onAISuggest: { activeSheet = .aiPlanning }
                )
                Divider()
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        WeekGrid(
                            days: days,
                            allLessonAssignments: weekLessonAssignments,
                            availableWidth: geometry.size.width - (UIConstants.contentHorizontalPadding * 2),
                            availableHeight: geometry.size.height,
                            onSelectLesson: { la in if let id = la.id { activeSheet = .presentationDetail(id) } },
                            onQuickActions: { la in if let id = la.id { activeSheet = .quickActions(id) } },
                            onPlanNext: { la in planNextLesson(for: la) }
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
                            await PlanningActions.pushLessonsWithAbsentStudents(
                                in: days,
                                calendar: calendar,
                                context: viewContext
                            )
                            onRefreshNeeded?()
                        }
                    } label: {
                        Label("Absent → Next Day", systemImage: "person.fill.xmark")
                    }
                    Button {
                        Task {
                            await PlanningActions.pushAllLessonsByOneDay(
                                in: days,
                                calendar: calendar,
                                context: viewContext
                            )
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
            loadWeekLessonAssignments()
        }
        .onChange(of: startDate) { _, _ in
            Task { @MainActor in
                loadWeekLessonAssignments()
            }
        }
        .onChange(of: inboxLessonIDs) { _, _ in
            syncInboxOrderWithCurrentBase()
        }
        .onChange(of: appRouter.planningInboxRefreshTrigger) { _, _ in
            // Reload week data when external changes occur (e.g., lessons scheduled/unscheduled)
            loadWeekLessonAssignments()
        }
    }

    // MARK: - Helpers
    private var weekRangeString: String {
        guard let first = days.first, let last = days.last else { return "" }
        let start = DateFormatters.shortMonthDay.string(from: first)
        let end = DateFormatters.shortMonthDay.string(from: last)
        return "\(start) - \(end)"
    }

    /// Synchronous helper that determines if a date is a non-school day using direct NSManagedObjectContext fetches.
    /// Rules:
    /// - Explicit CDNonSchoolDay records mark weekdays as non-school
    /// - Weekends are non-school by default unless a CDSchoolDayOverride exists for that date
    private func isNonSchoolDay(_ day: Date) -> Bool {
        let day = calendar.startOfDay(for: day)

        // 1) Explicit non-school day wins
        do {
            let nsDescriptor = { let r = NSFetchRequest<CDNonSchoolDay>(entityName: "NonSchoolDay"); r.predicate = NSPredicate(format: "date == %@", day as CVarArg); r.fetchLimit = 1; return r }()
            let nonSchoolDays: [CDNonSchoolDay] = try viewContext.fetch(nsDescriptor)
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
            let ovDescriptor = { let r = NSFetchRequest<CDSchoolDayOverride>(entityName: "SchoolDayOverride"); r.predicate = NSPredicate(format: "date == %@", day as CVarArg); r.fetchLimit = 1; return r }()
            let overrides: [CDSchoolDayOverride] = try viewContext.fetch(ovDescriptor)
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

    private func computeInitialStartDate() {
        let today = calendar.startOfDay(for: Date())
        let scheduledRaw = LessonAssignmentState.scheduled.rawValue

        let descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(format: "stateRaw == %@", scheduledRaw as CVarArg)
        descriptor.sortDescriptors = [NSSortDescriptor(key: "scheduledForDay", ascending: true)]
        descriptor.fetchLimit = 1

        if let nextUp = viewContext.safeFetchFirst(descriptor),
           let date = nextUp.scheduledFor {
            let start = calendar.startOfDay(for: date)
            if start >= today && !isNonSchoolDay(start) {
                self.startDate = start
                return
            }
        }

        self.startDate = firstSchoolDay(onOrAfter: today)
    }

    @MainActor
    private func syncInboxOrderWithCurrentBase() {
        let baseIDs = inboxLessons.compactMap(\.id)
        var order = InboxOrderStore.parse(inboxOrderRaw).filter { baseIDs.contains($0) }
        let missing = inboxLessons
            .filter { guard let id = $0.id else { return false }; return !order.contains(id) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            .compactMap(\.id)
        order.append(contentsOf: missing)
        inboxOrderRaw = InboxOrderStore.serialize(order)
    }
    
    // MARK: - Action Handlers
    
    private func handlePrevWeek() {
        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            moveStart(bySchoolDays: -7)
        }
    }

    private func handleNextWeek() {
        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            moveStart(bySchoolDays: 7)
        }
    }

    private func handleToday() {
        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            computeInitialStartDate()
        }
    }
    
    private func handleAddNew() {
        let newLA = PresentationFactory.makeDraft(lessonID: UUID(), studentIDs: [], context: managedObjectContext)
        presentationRepository.save(reason: "Creating new presentation")
        if let laID = newLA.id {
            activeSheet = .giveLessonDraft(laID)
        }
        onRefreshNeeded?()
    }
}
