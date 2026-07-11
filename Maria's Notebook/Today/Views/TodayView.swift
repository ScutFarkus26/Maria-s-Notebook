// swiftlint:disable file_length
// TodayView.swift
// Today hub showing reminders, lessons, scheduled check-ins, follow-ups, and completions.
// Integrated AttendanceView expansion logic with fixed roll-down animation.
//
// Split into multiple files for maintainability:
// - TodayView.swift (this file) - Main view structure and body
// - TodayViewSections.swift - All list sections (reminders, lessons, etc.)
// - TodayViewHeader.swift - Header and attendance strip components
// - TodayViewHelpers.swift - School day helpers and utility functions
// - TodayViewListRows.swift - Individual row components
// - AttendanceExpandedView.swift - Expanded attendance grid
// - SchoolDayCache.swift - School day caching

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog
import TipKit
#if os(iOS)
import MessageUI
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// Today hub view. Binds to TodayViewModel and renders multiple sections.
// swiftlint:disable:next type_body_length
struct TodayView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.appRouter) var appRouter
    @Environment(\.calendar) var calendar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RestoreCoordinator.self) var restoreCoordinator
    @Environment(SaveCoordinator.self) var saveCoordinator
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // MARK: - ViewModel
    @State var viewModel: TodayViewModel

    // MARK: - Navigation State
    @State var selectedWorkID: UUID?
    @State var selectedLessonAssignment: CDLessonAssignment?
    @State var isShowingQuickNote = false
    @State var pendingNoteStudentIDs: Set<UUID>?
    @State var noteBeingEdited: CDNote?

    // MARK: - Attendance State
    @State var isAttendanceExpanded = false

    // MARK: - Toast State
    @State var toastMessage: String?

    #if os(iOS)
    private let pullToRefreshTip = PullToRefreshTip()
    #endif

    // MARK: - Meeting State
    @State var selectedMeetingStudentID: UUID?
    @State var selectedMeetingID: UUID?

    // MARK: - Todo State
    @State var selectedTodoItem: CDTodoItem?
    @State var isShowingNewTodo = false

    // MARK: - Day Pad / Done Today / Day Cards State
    @AppStorage(UserDefaultsKeys.todayDayPadExpanded) var isDayPadExpanded: Bool = false
    @AppStorage(UserDefaultsKeys.todayDoneTodayExpanded) var isDoneTodayExpanded: Bool = false
    /// Bumped when a day card is dismissed to force the section to recompute.
    @State var dayCardsRefreshTrigger: Int = 0
    @State var needsLessonCount: Int = 0

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: false)],
        predicate: NSPredicate(format: "isCompleted == NO")
    ) var todayTodoItems: FetchedResults<CDTodoItem>

    // MARK: - Filtered Query State
    // ENERGY OPTIMIZATION: Filter change detection queries to only the relevant date window
    @State var filteredPresentationIDs: [UUID] = []
    @State var filteredPlanItemIDs: [UUID] = []

    // MARK: - School Day Cache
    @State var schoolDayCache = SchoolDayCache()

    // MARK: - Day Rollover
    /// The school-day-coerced date that currently represents "today".
    /// When the calendar day changes we only auto-advance `viewModel.date`
    /// if it still equals this anchor — a deliberately chosen date is kept.
    @State private var todayAnchor: Date?

    // MARK: - Computed Properties
    private var presentationIDs: [UUID] { filteredPresentationIDs }
    private var planItemIDs: [UUID] { filteredPlanItemIDs }

    /// Returns true if we're on iPhone compact layout where attendance has its own tab
    private var isIPhoneCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    // MARK: - Init
    init(context: NSManagedObjectContext) {
        _viewModel = State(wrappedValue: TodayViewModel(context: context, calendar: AppCalendar.shared))
    }

    // MARK: - Body

    var body: some View {
        rootContent
            .task(priority: .userInitiated) {
                await handleViewAppear()
            }
            .onChange(of: calendar) { _, newCal in
                viewModel.setCalendar(newCal)
                AppCalendar.adopt(timeZoneFrom: newCal)
            }
            .onChange(of: viewModel.date) { _, newValue in
                handleDateChange(newValue)
            }
            .onChange(of: appRouter.planningInboxRefreshTrigger) { _, _ in
                viewModel.reload()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            #if os(macOS)
            .onChange(of: selectedWorkID) { _, workID in
                guard let workID else { return }
                openWindow(id: "WorkDetailWindow", value: workID)
                selectedWorkID = nil
            }
            .onChange(of: selectedLessonAssignment?.id) { _, _ in
                guard let lessonAssignmentID = selectedLessonAssignment?.id else { return }
                openWindow(id: "PresentationDetailWindow", value: lessonAssignmentID)
                selectedLessonAssignment = nil
            }
            .onChange(of: noteBeingEdited?.id) { _, _ in
                guard let noteID = noteBeingEdited?.id else { return }
                openWindow(id: "NoteEditorWindow", value: noteID)
                noteBeingEdited = nil
            }
            .onChange(of: selectedMeetingStudentID) { _, studentID in
                guard let studentID else { return }
                openWindow(
                    id: "MeetingSessionWindow",
                    value: MeetingSessionWindowPayload(
                        studentID: studentID,
                        scheduledMeetingID: selectedMeetingID
                    )
                )
                selectedMeetingStudentID = nil
                selectedMeetingID = nil
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .noteDidSave)) { _ in
                viewModel.reload()
            }
            .onCalendarDayChange {
                handleDayChange()
            }
            .modifier(TodayViewSheets(
                selectedWorkID: $selectedWorkID,
                selectedLessonAssignment: $selectedLessonAssignment,
                isShowingQuickNote: $isShowingQuickNote,
                pendingNoteStudentIDs: $pendingNoteStudentIDs,
                selectedTodoItem: $selectedTodoItem,
                isShowingNewTodo: $isShowingNewTodo,
                noteBeingEdited: $noteBeingEdited,
                selectedMeetingStudentID: $selectedMeetingStudentID,
                selectedMeetingID: $selectedMeetingID,
                viewContext: viewContext,
                onReload: { viewModel.reload() }
            ))
            .overlay(alignment: .top) {
                toastOverlay
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        if restoreCoordinator.isRestoring {
            restoringView
        } else {
            mainContent
        }
    }

    // MARK: - View Components

    private var restoringView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Restoring data…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // On iPhone compact, attendance has its own tab, so hide it here.
                // Otherwise render the strip (and expanded grid, if open) above the
                // list so the user can mark attendance without losing scroll position.
                if !isIPhoneCompact {
                    attendanceSection
                }
                listContent
            }
            .navigationTitle("Today")
            #if os(macOS)
            .toolbar { macOSTodayToolbarContent }
            #else
            .toolbar { toolbarContent }
            #endif
        }
    }

    private var attendanceSection: some View {
        VStack(spacing: 0) {
            attendanceStrip
                .padding(.horizontal, 16)

            if isAttendanceExpanded {
                AttendanceExpandedView(
                    date: viewModel.date,
                    isNonSchoolDay: isNonSchoolDaySync(viewModel.date),
                    onChange: { viewModel.reload() },
                    onToast: { message in toast(message) }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 10)
        .padding(.bottom, isAttendanceExpanded ? 8 : 10)
    }

    private var listContent: some View {
        #if os(macOS)
        twoColumnLayout
        #else
        List {
            TipView(pullToRefreshTip)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            // What's next, then today's surfaces
            rightNowListSection
            deadlinesListSection
            dayCardsListSection
            agendaListSection
            todosListSection
            calendarEventsListSection
            remindersListSection
            dayPadListSection
            recentNotesListSection
            doneTodayListSection
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.reload()
            reloadDerivedCounts()
            pullToRefreshTip.invalidate(reason: .actionPerformed)
        }
        #endif
    }

    #if os(macOS)
    private var twoColumnLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column: glanceable surfaces; Right column: live agenda
            List {
                rightNowListSection
                deadlinesListSection
                dayCardsListSection
                todosListSection
                calendarEventsListSection
                remindersListSection
                dayPadListSection
                recentNotesListSection
                doneTodayListSection
            }
            .listStyle(.inset)
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

            Divider()

            rightColumnContent
        }
    }

    @ViewBuilder
    private var rightColumnContent: some View {
        if let selectedTodoItem {
            VStack(spacing: 0) {
                HStack {
                    Text("Edit Todo")
                        .font(AppTheme.ScaledFont.body.weight(.semibold))
                    Spacer()
                    Button("Done") {
                        self.selectedTodoItem = nil
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                EditTodoForm(todo: selectedTodoItem)
            }
        } else {
            // Right column: Agenda (lessons + work items)
            List {
                agendaListSection
            }
            .listStyle(.inset)
        }
    }
    #endif

    #if os(iOS)
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                let prev = previousSchoolDaySync(before: viewModel.date)
                viewModel.date = AppCalendar.startOfDay(prev)
            } label: { Image(systemName: "chevron.left") }

            DatePicker("Date", selection: Binding(get: { viewModel.date }, set: { newValue in
                let coerced = nearestSchoolDaySync(to: newValue)
                viewModel.date = AppCalendar.startOfDay(coerced)
            }), displayedComponents: .date)
            .datePickerStyle(.compact)

            Button {
                let next = nextSchoolDaySync(after: viewModel.date)
                viewModel.date = AppCalendar.startOfDay(next)
            } label: { Image(systemName: "chevron.right") }
        }

        ToolbarSpacer(.flexible, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Button("Today") {
                let today = Date()
                let coerced = nearestSchoolDaySync(to: today)
                viewModel.date = AppCalendar.startOfDay(coerced)
            }
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            toolbarPlusMenu
        }
    }

    #endif

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = toastMessage {
            Text(message)
                .font(AppTheme.ScaledFont.captionSemibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(UIConstants.OpacityConstants.nearSolid))
                )
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.moderate), radius: 6, x: 0, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
        }
    }

    // MARK: - Event Handlers

    // PERF: Structured concurrency — async let runs both syncs in parallel
    // while inheriting .task cancellation (no more fire-and-forget Task blocks).
    private func handleViewAppear() async {
        viewModel.setCalendar(calendar)
        async let reminderSync: Void = syncReminders()
        async let calendarSync: Void = syncCalendarEvents()
        AppCalendar.adopt(timeZoneFrom: calendar)
        let coerced = nearestSchoolDaySync(to: viewModel.date)
        if coerced != viewModel.date {
            viewModel.date = AppCalendar.startOfDay(coerced)
        }
        if todayAnchor == nil {
            todayAnchor = AppCalendar.startOfDay(coerced)
        }
        handleDayChange()
        updateFilteredQueries()
        reloadDerivedCounts()
        // Await both syncs — cancellation propagates automatically when view disappears
        _ = await (reminderSync, calendarSync)
    }

    /// Recomputes counts that drive the day-aware cards (needs-lesson).
    /// Called on appear, refresh, and date change.
    func reloadDerivedCounts() {
        needsLessonCount = computeNeedsLessonCount()
    }

    private func computeNeedsLessonCount() -> Int {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.enrolledPredicate
        let students = TestStudentsFilter.filterVisible(viewContext.safeFetch(request)).uniqueByID
        guard !students.isEmpty else { return 0 }
        let viewModel = StudentsViewModel()
        let daysMap = viewModel.computeDaysSinceLastLessonCache(
            for: students,
            using: viewContext,
            calendar: calendar
        )
        // Count students who've never been presented (-1) OR overdue (>= 7 days)
        return daysMap.values.filter { $0 == -1 || $0 >= 7 }.count
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // Resume syncs when app becomes active
            Task {
                async let reminderSync: Void = syncReminders()
                async let calendarSync: Void = syncCalendarEvents()
                _ = await (reminderSync, calendarSync)
            }
        case .inactive, .background:
            // App is inactive or in background - expensive syncs will be paused automatically
            // because sync Tasks check for cancellation
            break
        @unknown default:
            break
        }
    }

    /// Rolls `viewModel.date` forward when the calendar day changes so agenda
    /// and attendance actions (e.g. "Mark All Present") never target a stale
    /// "today" after an overnight suspension. Idempotent — called at midnight,
    /// on scene activation, and on appear.
    private func handleDayChange() {
        let newAnchor = AppCalendar.startOfDay(nearestSchoolDaySync(to: Date()))
        guard newAnchor != todayAnchor else { return }
        if todayAnchor == nil || viewModel.date == todayAnchor {
            viewModel.date = newAnchor
        }
        todayAnchor = newAnchor
    }

    private func handleDateChange(_ newValue: Date) {
        let coerced = nearestSchoolDaySync(to: newValue)
        let startOfDay = AppCalendar.startOfDay(coerced)

        // Only update if the coerced date is different to prevent feedback loops
        if startOfDay != newValue && startOfDay != AppCalendar.startOfDay(newValue) {
            viewModel.date = startOfDay
            return
        }

        updateFilteredQueries()
        reloadDerivedCounts()
    }

    // PERF: Async functions instead of fire-and-forget Task blocks.
    // Callers use structured concurrency (async let / .task) for automatic cancellation.
    private func syncReminders() async {
        let syncService = ReminderSyncService.shared
        syncService.managedObjectContext = viewContext
        if syncService.syncListIdentifier != nil || syncService.syncListName != nil {
            do {
                try await syncService.syncReminders()
            } catch {
                #if DEBUG
                Logger.sync.error("CDReminder sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func syncCalendarEvents() async {
        let calendarSyncService = CalendarSyncService.shared
        calendarSyncService.managedObjectContext = viewContext
        if !calendarSyncService.syncCalendarIdentifiers.isEmpty {
            do {
                try await calendarSyncService.syncEvents()
            } catch {
                #if DEBUG
                Logger.sync.error("Calendar sync failed: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

// MARK: - Supporting Files
// - TodayViewSections.swift - All list sections (reminders, lessons, etc.)
// - TodayViewHeader.swift - Header and attendance strip components
// - TodayViewHelpers.swift - School day helpers and utility functions
// - TodayViewListRows.swift - Individual row components
// - AttendanceExpandedView.swift - Expanded attendance grid
// - SchoolDayCache.swift - School day caching

// MARK: - Sheets Modifier
// Bundles all of TodayView's sheet presentations into a single ViewModifier so
// the body's modifier chain stays short enough for the type checker.
private struct TodayViewSheets: ViewModifier {
    @Binding var selectedWorkID: UUID?
    @Binding var selectedLessonAssignment: CDLessonAssignment?
    @Binding var isShowingQuickNote: Bool
    @Binding var pendingNoteStudentIDs: Set<UUID>?
    @Binding var selectedTodoItem: CDTodoItem?
    @Binding var isShowingNewTodo: Bool
    @Binding var noteBeingEdited: CDNote?
    @Binding var selectedMeetingStudentID: UUID?
    @Binding var selectedMeetingID: UUID?
    let viewContext: NSManagedObjectContext
    let onReload: () -> Void

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .sheet(id: $selectedWorkID) { id in
                WorkDetailView(workID: id) {
                    selectedWorkID = nil
                    onReload()
                }
            }
            #endif
            #if os(iOS)
                .sheet(item: $selectedLessonAssignment) { la in
                    lessonAssignmentSheet(la)
                }
            #endif
            .sheet(
                isPresented: $isShowingQuickNote,
                onDismiss: { pendingNoteStudentIDs = nil },
                content: { quickNoteSheetContent }
            )
#if os(iOS)
            .sheet(item: $selectedTodoItem) { todo in
                editTodoSheet(todo)
            }
#endif
            .sheet(isPresented: $isShowingNewTodo) {
                newTodoSheet
            }
            #if os(iOS)
            .sheet(item: $noteBeingEdited) { note in
                noteEditSheet(note)
            }
            #endif
            #if os(iOS)
            .sheet(id: $selectedMeetingStudentID) { studentID in
                meetingSessionSheet(studentID)
            }
            #endif
    }

    private func lessonAssignmentSheet(_ la: CDLessonAssignment) -> some View {
        PresentationDetailView(lessonAssignment: la) {
            selectedLessonAssignment = nil
        }
#if os(macOS)
        .frame(minWidth: 720, minHeight: 640)
        .presentationSizingFitted()
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }

    @ViewBuilder
    private var quickNoteSheetContent: some View {
        if let preselected = pendingNoteStudentIDs {
            QuickNoteSheet(initialStudentIDs: preselected)
        } else {
            QuickNoteSheet()
        }
    }

#if os(iOS)
    private func editTodoSheet(_ todo: CDTodoItem) -> some View {
        NavigationStack {
            EditTodoForm(todo: todo)
                .navigationTitle("Edit Todo")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            selectedTodoItem = nil
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
#endif

    private var newTodoSheet: some View {
        NavigationStack {
            NewTodoForm()
                .navigationTitle("New Todo")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isShowingNewTodo = false
                        }
                    }
                }
        }
    }

    private func noteEditSheet(_ note: CDNote) -> some View {
        NoteEditSheet(note: note) {
            onReload()
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        .presentationSizingFitted()
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }

    private func meetingSessionSheet(_ studentID: UUID) -> some View {
        ScheduledMeetingSessionSheet(studentID: studentID) {
            if let meetingID = selectedMeetingID {
                MeetingScheduler.clearMeeting(id: meetingID, context: viewContext)
            }
            selectedMeetingStudentID = nil
            selectedMeetingID = nil
            onReload()
        }
#if os(macOS)
        .frame(minWidth: 860, minHeight: 640)
        .presentationSizingFitted()
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }
}
