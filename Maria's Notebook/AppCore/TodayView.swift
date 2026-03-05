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
import SwiftData
import UniformTypeIdentifiers
import OSLog
#if os(iOS)
import MessageUI
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// Today hub view. Binds to TodayViewModel and renders multiple sections.
struct TodayView: View {
    // MARK: - Environment
    @Environment(\.modelContext) var modelContext
    @Environment(\.appRouter) var appRouter
    @Environment(\.calendar) var calendar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RestoreCoordinator.self) var restoreCoordinator
    @Environment(SaveCoordinator.self) var saveCoordinator
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // MARK: - ViewModel
    @State var viewModel: TodayViewModel

    // MARK: - Navigation State
    @State var selectedWorkID: UUID?
    @State var selectedLessonAssignment: LessonAssignment?
    @State var isShowingQuickNote = false
    @State var noteBeingEdited: Note?

    // MARK: - Attendance State
    @State var isAttendanceExpanded = false

    // MARK: - Toast State
    @State var toastMessage: String?

    // MARK: - Todo State
    @State var selectedTodoItem: TodoItem?
    @State var isShowingNewTodo = false
    @Query(
        filter: #Predicate<TodoItem> { !$0.isCompleted },
        sort: \TodoItem.createdAt,
        order: .reverse
    ) var todayTodoItems: [TodoItem]

    // MARK: - Filtered Query State
    // ENERGY OPTIMIZATION: Filter change detection queries to only the relevant date window
    @State var filteredPresentationIDs: [UUID] = []
    @State var filteredPlanItemIDs: [UUID] = []

    // MARK: - School Day Cache
    @State var schoolDayCache = SchoolDayCache()

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
    init(context: ModelContext) {
        _viewModel = State(wrappedValue: TodayViewModel(context: context, calendar: AppCalendar.shared))
    }

    // MARK: - Body

    var body: some View {
        Group {
            if restoreCoordinator.isRestoring {
                restoringView
            } else {
                mainContent
            }
        }
        // PERFORMANCE: Use .task instead of .onAppear for automatic cancellation
        // .task automatically cancels when view disappears, preventing unnecessary work
        .task(priority: .userInitiated) {
            handleViewAppear()
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
        // PERFORMANCE: Pause expensive syncs when app is in background
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .sheet(id: $selectedWorkID) { id in
            WorkDetailView(workID: id) {
                selectedWorkID = nil
                viewModel.reload()
            }
        }
        .sheet(item: $selectedLessonAssignment) { la in
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
        .sheet(isPresented: $isShowingQuickNote) {
            QuickNoteSheet()
        }
#if os(iOS)
        .sheet(item: $selectedTodoItem) { todo in
            NavigationStack {
                EditTodoForm(todo: todo)
                    .navigationTitle("Edit Todo")
                    .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $isShowingNewTodo) {
            NavigationStack {
                NewTodoForm()
                    .navigationTitle("New Todo")
                    #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isShowingNewTodo = false
                            }
                        }
                    }
            }
        }
        .sheet(item: $noteBeingEdited) { note in
            NoteEditSheet(note: note) {
                viewModel.reload()
            }
#if os(macOS)
            .frame(minWidth: 520, minHeight: 420)
            .presentationSizingFitted()
#else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
#endif
        }
        .overlay(alignment: .top) {
            toastOverlay
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
                #if os(macOS)
                header
                Divider()
                #endif

                // On iPhone compact, attendance has its own tab, so hide it here
                if !isIPhoneCompact {
                    attendanceSection

                    if !isAttendanceExpanded {
                        listContent
                    }
                } else {
                    listContent
                }
            }
            .navigationTitle("Today")
            #if os(iOS)
            .toolbar { toolbarContent }
            #endif
        }
        #if os(iOS)
        .simultaneousGesture(swipeGesture)
        #endif
    }

    private var attendanceSection: some View {
        Group {
            if isAttendanceExpanded {
                VStack(spacing: 0) {
                    attendanceStrip
                        .padding(.horizontal, 16)

                    AttendanceExpandedView(
                        date: viewModel.date,
                        isNonSchoolDay: isNonSchoolDaySync(viewModel.date),
                        onChange: { viewModel.reload() },
                        onToast: { message in toast(message) }
                    )
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                .frame(maxHeight: .infinity)
                .padding(.top, 10)
            } else {
                VStack(spacing: 0) {
                    attendanceStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
                .padding(.top, 10)
            }
        }
    }

    private var listContent: some View {
        #if os(macOS)
        twoColumnLayout
        #else
        List {
            calendarEventsListSection
            todosListSection
            remindersListSection
            presentedLessonsListSection
            checkedWorkListSection
            agendaListSection
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.reload()
        }
        #endif
    }

    #if os(macOS)
    private var twoColumnLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column: Calendar + Todos + Reminders + Lessons Presented + Work Checked
            List {
                calendarEventsListSection
                todosListSection
                remindersListSection
                presentedLessonsListSection
                checkedWorkListSection
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

            Button("Today") {
                let today = Date()
                let coerced = nearestSchoolDaySync(to: today)
                viewModel.date = AppCalendar.startOfDay(coerced)
            }

            Button {
                isShowingQuickNote = true
            } label: {
                Label("Note", systemImage: "square.and.pencil")
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 80)
            .onEnded { value in
                let horizontalAmount = value.translation.width
                let verticalAmount = value.translation.height
                if abs(horizontalAmount) > abs(verticalAmount) * 1.5 && abs(horizontalAmount) > 80 {
                    if horizontalAmount > 0 {
                        let prev = previousSchoolDaySync(before: viewModel.date)
                        viewModel.date = AppCalendar.startOfDay(prev)
                    } else {
                        let next = nextSchoolDaySync(after: viewModel.date)
                        viewModel.date = AppCalendar.startOfDay(next)
                    }
                }
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
                        .fill(Color.black.opacity(0.85))
                )
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
        }
    }

    // MARK: - Event Handlers

    private func handleViewAppear() {
        viewModel.setCalendar(calendar)
        syncReminders()
        syncCalendarEvents()
        AppCalendar.adopt(timeZoneFrom: calendar)
        let coerced = nearestSchoolDaySync(to: viewModel.date)
        if coerced != viewModel.date {
            viewModel.date = AppCalendar.startOfDay(coerced)
        }
        updateFilteredQueries()
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // Resume syncs when app becomes active
            syncReminders()
            syncCalendarEvents()
        case .inactive, .background:
            // App is inactive or in background - expensive syncs will be paused automatically
            // because sync Tasks check for cancellation
            break
        @unknown default:
            break
        }
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
    }

    private func syncReminders() {
        Task {
            let syncService = ReminderSyncService.shared
            syncService.modelContext = modelContext
            if syncService.syncListIdentifier != nil || syncService.syncListName != nil {
                do {
                    try await syncService.syncReminders()
                } catch {
                    #if DEBUG
                    Logger.sync.error("Reminder sync failed: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }

    private func syncCalendarEvents() {
        Task {
            let calendarSyncService = CalendarSyncService.shared
            calendarSyncService.modelContext = modelContext
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
}

// MARK: - Supporting Files
// - TodayViewSections.swift - All list sections (reminders, lessons, etc.)
// - TodayViewHeader.swift - Header and attendance strip components
// - TodayViewHelpers.swift - School day helpers and utility functions
// - TodayViewListRows.swift - Individual row components
// - AttendanceExpandedView.swift - Expanded attendance grid
// - SchoolDayCache.swift - School day caching
