// TodayView.swift
// Today hub showing reminders, lessons, scheduled check-ins (WorkPlanItem), follow-ups (Stale Contracts), and completions.
// Updated to use WorkContract and WorkPlanItem instead of legacy WorkCheckIn.
// Integrated AttendanceView expansion logic with fixed roll-down animation.

import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers
#if os(iOS)
import MessageUI
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// Helper class to cache school day data for TodayView
/// This avoids repeated database fetches when iterating through dates
private class SchoolDayCache {
    var cachedNonSchoolDays: Set<Date> = []
    var cachedSchoolDayOverrides: Set<Date> = []
    var cachedYearRange: ClosedRange<Int>?
    
    func cacheSchoolDayData(for date: Date, modelContext: ModelContext) {
        let cal = AppCalendar.shared
        let year = cal.component(.year, from: date)
        let yearRange = (year - 1)...(year + 1)
        
        // Check if we already have cached data for this year range
        if let cachedRange = cachedYearRange,
           cachedRange.contains(year) {
            return // Cache is still valid
        }
        
        // Calculate date range for 2-year window (1 year before to 1 year after)
        guard let startDate = cal.date(from: DateComponents(year: year - 1, month: 1, day: 1)),
              let endDate = cal.date(from: DateComponents(year: year + 2, month: 1, day: 1)) else {
            return
        }
        
        let startOfWindow = AppCalendar.startOfDay(startDate)
        let endOfWindow = AppCalendar.startOfDay(endDate)
        
        // Fetch all NonSchoolDay records in the window
        do {
            let nsDescriptor = FetchDescriptor<NonSchoolDay>(
                predicate: #Predicate<NonSchoolDay> { nsd in
                    nsd.date >= startOfWindow && nsd.date < endOfWindow
                }
            )
            let nonSchoolDays = try modelContext.fetch(nsDescriptor)
            cachedNonSchoolDays = Set(nonSchoolDays.map { AppCalendar.startOfDay($0.date) })
        } catch {
            cachedNonSchoolDays = []
        }
        
        // Fetch all SchoolDayOverride records in the window
        do {
            let ovDescriptor = FetchDescriptor<SchoolDayOverride>(
                predicate: #Predicate<SchoolDayOverride> { sdo in
                    sdo.date >= startOfWindow && sdo.date < endOfWindow
                }
            )
            let overrides = try modelContext.fetch(ovDescriptor)
            cachedSchoolDayOverrides = Set(overrides.map { AppCalendar.startOfDay($0.date) })
        } catch {
            cachedSchoolDayOverrides = []
        }
        
        cachedYearRange = yearRange
    }
    
    func isNonSchoolDay(_ date: Date) -> Bool {
        let day = AppCalendar.startOfDay(date)
        let cal = AppCalendar.shared

        // 1) Explicit non-school day wins (check cache)
        if cachedNonSchoolDays.contains(day) {
            return true
        }

        // 2) Weekends are non-school by default (Sunday=1, Saturday=7)
        let weekday = cal.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }

        // 3) Weekend override makes it a school day (check cache)
        if cachedSchoolDayOverrides.contains(day) {
            return false
        }
        
        return true
    }
}

/// Today hub view. Binds to TodayViewModel and renders multiple sections.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var restoreCoordinator: RestoreCoordinator
    // Add SaveCoordinator if available in environment, otherwise we might handle saves locally,
    // but Attendance logic relies on it.
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @StateObject private var viewModel: TodayViewModel

    // Navigation state
    @State private var selectedWorkID: UUID? = nil
    @State private var selectedStudentLesson: StudentLesson? = nil
    @State private var isShowingQuickNote = false
    @State private var noteBeingEdited: Note? = nil
    
    // Attendance Expansion State
    @State private var isAttendanceExpanded = false

    // ENERGY OPTIMIZATION: Filter change detection queries to only the relevant date window to avoid loading the entire database.
    // This significantly reduces memory usage and database query overhead by monitoring only lessons and plan items
    // that could affect the Today screen's display for the current date.
    @State private var filteredStudentLessonIDs: [UUID] = []
    @State private var filteredPlanItemIDs: [UUID] = []
    
    // School day cache to avoid repeated database fetches in date calculation loops
    @State private var schoolDayCache = SchoolDayCache()
    
    // Computed properties that fetch filtered data for change detection
    // Filter StudentLesson to only lessons scheduled for the current day window [viewModel.date.startOfDay, nextDay)
    private var studentLessonIDs: [UUID] {
        filteredStudentLessonIDs
    }
    
    // Filter WorkPlanItem to only items where scheduledDate <= nextDay (covers overdue + today)
    private var planItemIDs: [UUID] {
        filteredPlanItemIDs
    }
    
    // Helper to update filtered queries when date or data changes
    private func updateFilteredQueries() {
        let (dayStart, dayEnd) = AppCalendar.dayRange(for: viewModel.date)
        
        // Fetch filtered StudentLesson IDs
        do {
            let lessonDescriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate<StudentLesson> { lesson in
                    lesson.scheduledForDay >= dayStart && lesson.scheduledForDay < dayEnd
                },
                sortBy: [SortDescriptor(\StudentLesson.id)]
            )
            let lessons = try modelContext.fetch(lessonDescriptor)
            filteredStudentLessonIDs = lessons.map { $0.id }
        } catch {
            filteredStudentLessonIDs = []
        }
        
        // Fetch filtered WorkPlanItem IDs
        do {
            let planDescriptor = FetchDescriptor<WorkPlanItem>(
                predicate: #Predicate<WorkPlanItem> { item in
                    item.scheduledDate <= dayEnd
                },
                sortBy: [SortDescriptor(\WorkPlanItem.id)]
            )
            let planItems = try modelContext.fetch(planDescriptor)
            filteredPlanItemIDs = planItems.map { $0.id }
        } catch {
            filteredPlanItemIDs = []
        }
    }
    
    // MARK: - Helpers
    
    /// Synchronous helper that determines if a date is a non-school day using cached data.
    private func isNonSchoolDaySync(_ date: Date) -> Bool {
        schoolDayCache.cacheSchoolDayData(for: date, modelContext: modelContext)
        return schoolDayCache.isNonSchoolDay(date)
    }
    
    /// Synchronous helper that returns the next school day strictly after the given date.
    private func nextSchoolDaySync(after date: Date) -> Date {
        // Cache school day data once at the start to avoid repeated database fetches
        schoolDayCache.cacheSchoolDayData(for: date, modelContext: modelContext)
        
        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        // Start from the following day
        d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        // Safety cap to avoid infinite loops in case of data errors
        for _ in 0..<730 { // up to ~2 years
            if !schoolDayCache.isNonSchoolDay(d) { return d }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }
    
    /// Synchronous helper that returns the previous school day strictly before the given date.
    private func previousSchoolDaySync(before date: Date) -> Date {
        // Cache school day data once at the start to avoid repeated database fetches
        schoolDayCache.cacheSchoolDayData(for: date, modelContext: modelContext)
        
        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        // Start from the previous day
        d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        for _ in 0..<730 { // up to ~2 years
            if !schoolDayCache.isNonSchoolDay(d) { return d }
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }
    
    /// Synchronous helper that coerces the provided date to the nearest school day.
    private func nearestSchoolDaySync(to date: Date) -> Date {
        // Cache school day data once at the start to avoid repeated database fetches
        schoolDayCache.cacheSchoolDayData(for: date, modelContext: modelContext)
        
        let day = AppCalendar.startOfDay(date)
        if !schoolDayCache.isNonSchoolDay(day) { return day }
        let prev = previousSchoolDaySync(before: day)
        let next = nextSchoolDaySync(after: day)
        let distPrev = abs(prev.timeIntervalSince(day))
        let distNext = abs(next.timeIntervalSince(day))
        if distPrev < distNext { return prev }
        // On tie or next closer, prefer next
        return next
    }
    
    // Helpers
    // PERFORMANCE OPTIMIZATION: Use ViewModel helpers to avoid recreating closures
    private func nameForLesson(_ id: UUID) -> String {
        viewModel.lessonName(for: id)
    }
    
    // PERFORMANCE OPTIMIZATION: Use cached duplicate names from ViewModel
    private var duplicateFirstNames: Set<String> {
        viewModel.duplicateFirstNames
    }

    // PERFORMANCE OPTIMIZATION: Use ViewModel helper to avoid recreating closures
    private func displayNameForID(_ id: UUID) -> String {
        viewModel.displayName(for: id)
    }

    // PERFORMANCE OPTIMIZATION: Use function instead of closure
    private func studentNamesForIDs(_ ids: [UUID]) -> String {
        let names = ids.map { displayNameForID($0) }
        return names.joined(separator: ", ")
    }
    
    private func studentNames(for note: Note) -> String {
        switch note.scope {
        case .all: return ""
        case .student(let id):
            if let _ = viewModel.recentNoteStudentsByID[id] { return displayNameForID(id) }
            return ""
        case .students(let ids):
            let names = ids.compactMap { sid in viewModel.recentNoteStudentsByID[sid].map { _ in displayNameForID(sid) } }
            return names.prefix(3).joined(separator: ", ")
        }
    }

    @ViewBuilder
    private func studentPill(_ name: String, color: Color) -> some View {
        Text(name)
            .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .textSelection(.disabled)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - Init
    init(context: ModelContext) {
        _viewModel = StateObject(wrappedValue: TodayViewModel(context: context, calendar: AppCalendar.shared))
    }

    var body: some View {
        Group {
            if restoreCoordinator.isRestoring {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Restoring data…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationStack {
                    VStack(spacing: 0) {
                        #if os(macOS)
                        header
                        Divider()
                        #endif
                        
                        // Modified Attendance Section
                        VStack(spacing: 0) {
                            attendanceStrip
                                .zIndex(1) // Keep the strip above the animation
                                .padding(.horizontal, 16)
                                .padding(.bottom, isAttendanceExpanded ? 0 : 10)
                            
                            // Wrapping in a clipped VStack ensures the view "rolls down" from the bottom of the strip
                            // instead of sliding from the top of the entire container (behind the strip).
                            VStack(spacing: 0) {
                                if isAttendanceExpanded {
                                    AttendanceExpandedView(
                                        date: viewModel.date,
                                        isNonSchoolDay: isNonSchoolDaySync(viewModel.date),
                                        onChange: {
                                            // When attendance changes in the expanded view, reload the Today summary
                                            viewModel.reload()
                                        }
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 16)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .clipped() // Clip content to this wrapper's bounds (hiding it when "behind" the strip)
                            .zIndex(0)
                        }
                        .padding(.top, 10)
                        
                        List {
                            remindersListSection
                            
                            lessonsListSection
                            
                            checkInsListSection
                            
                            inProgressListSection
                            
                            completedListSection
                            
                            recentObservationsSection
                        }
                        #if os(iOS)
                        .listStyle(.insetGrouped)
                        #endif
                    }
                    .navigationTitle("Today")
                    #if os(iOS)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Picker("Level", selection: $viewModel.levelFilter) {
                                ForEach(TodayViewModel.LevelFilter.allCases, id: \.self) { f in
                                    Text(f.rawValue).tag(f)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                            
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
                    #endif
                }
                #if os(iOS)
                // PERFORMANCE OPTIMIZATION: Use simultaneousGesture to avoid interfering with List scrolling
                .simultaneousGesture(
                    DragGesture(minimumDistance: 80)
                        .onEnded { value in
                            let horizontalAmount = value.translation.width
                            let verticalAmount = value.translation.height
                            // Only trigger if horizontal swipe is significantly more than vertical
                            // This prevents conflicts with List scrolling
                            if abs(horizontalAmount) > abs(verticalAmount) * 1.5 && abs(horizontalAmount) > 80 {
                                // Horizontal swipe
                                if horizontalAmount > 0 {
                                    // Swipe right - go to previous day
                                    let prev = previousSchoolDaySync(before: viewModel.date)
                                    viewModel.date = AppCalendar.startOfDay(prev)
                                } else {
                                    // Swipe left - go to next day
                                    let next = nextSchoolDaySync(after: viewModel.date)
                                    viewModel.date = AppCalendar.startOfDay(next)
                                }
                            }
                        }
                )
                #endif
            }
        }
        .onAppear {
            viewModel.setCalendar(calendar)
            // Sync reminders when Today view appears
            Task {
                let syncService = ReminderSyncService.shared
                syncService.modelContext = modelContext
                if syncService.syncListName != nil {
                    do {
                        try await syncService.syncReminders()
                    } catch {
                        // Silently fail - user can manually sync from settings
                        print("TodayView: Reminder sync failed: \(error.localizedDescription)")
                    }
                }
            }
            AppCalendar.adopt(timeZoneFrom: calendar)
            // Ensure initial date is a school day
            let coerced = nearestSchoolDaySync(to: viewModel.date)
            if coerced != viewModel.date {
                viewModel.date = AppCalendar.startOfDay(coerced)
            }
            // Initialize filtered queries
            updateFilteredQueries()
        }
        .onChange(of: calendar) { _, newCal in
            viewModel.setCalendar(newCal)
            AppCalendar.adopt(timeZoneFrom: newCal)
        }
        .onChange(of: viewModel.date) { _, newValue in
            // Ensure date is always a school day
            let coerced = nearestSchoolDaySync(to: newValue)
            if coerced != newValue {
                viewModel.date = AppCalendar.startOfDay(coerced)
            }
            // Update filtered queries when date changes
            updateFilteredQueries()
            // Reset expansion if day changes? Optional. Keeping it open is usually better UX.
        }
        .onChange(of: appRouter.planningInboxRefreshTrigger) { _, _ in
            // Planning inbox refresh is user-initiated, so reload immediately
            viewModel.reload()
        }
        // Sheet for Contract Details
        .sheet(id: $selectedWorkID) { id in
            WorkDetailContainerView(workID: id) {
                selectedWorkID = nil
                viewModel.reload()
            }
        }
        // Sheet for Student Lesson Details
        .sheet(item: $selectedStudentLesson) { sl in
            StudentLessonDetailView(studentLesson: sl) {
                selectedStudentLesson = nil
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
    }
    
    private var recentObservationsSection: some View {
        Section {
            if viewModel.recentNotes.isEmpty {
                ContentUnavailableView("No recent observations", systemImage: "note.text")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.recentNotes, id: \.id) { note in
                    Button {
                        switch note.scope {
                        case .student(let id):
                            appRouter.requestOpenStudentDetail(id)
                        case .all, .students:
                            break
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "note.text").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.body.split(separator: "\n").first.map(String.init) ?? "")
                                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                let names = studentNames(for: note)
                                if !names.isEmpty {
                                    Text(names)
                                        .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(note.createdAt, style: note.createdAt > Date().addingTimeInterval(-3600*24*3) ? .relative : .date)
                                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                    }
                    .buttonStyle(.plain)
#if os(iOS)
                    .swipeActions(edge: .trailing) {
                        Button {
                            noteBeingEdited = note
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
#endif
                    .contextMenu {
                        Button {
                            noteBeingEdited = note
                        } label: {
                            Label("Edit Note", systemImage: "pencil")
                        }
                    }
                }
            }
        } header: {
            Label("Recent Observations", systemImage: "note.text")
        }
    }

    // MARK: - Header
    private var header: some View {
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Today")
                    .font(.system(size: AppTheme.FontSize.titleMedium, weight: .bold, design: .rounded))
                Spacer()
                Picker("Level", selection: $viewModel.levelFilter) {
                    ForEach(TodayViewModel.LevelFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            HStack(spacing: 12) {
                Button {
                    let prev = previousSchoolDaySync(before: viewModel.date)
                    viewModel.date = AppCalendar.startOfDay(prev)
                } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)

                DatePicker("Date", selection: Binding(get: { viewModel.date }, set: { newValue in
                    let coerced = nearestSchoolDaySync(to: newValue)
                    viewModel.date = AppCalendar.startOfDay(coerced)
                }), displayedComponents: .date)
#if os(macOS)
                .datePickerStyle(.field)
#else
                .datePickerStyle(.compact)
#endif

                Button {
                    let next = nextSchoolDaySync(after: viewModel.date)
                    viewModel.date = AppCalendar.startOfDay(next)
                } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)

                Button("Today") {
                    let today = Date()
                    let coerced = nearestSchoolDaySync(to: today)
                    viewModel.date = AppCalendar.startOfDay(coerced)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text(viewModel.date, format: Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day())
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Lessons: \(viewModel.todaysLessons.count)")
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Attendance Strip
    private var attendanceStrip: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isAttendanceExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                statChip(title: "Present", count: viewModel.attendanceSummary.presentCount, color: .green)
                statChip(title: "Absent", count: viewModel.attendanceSummary.absentCount, color: .red)
                statChip(title: "Left Early", count: viewModel.attendanceSummary.leftEarlyCount, color: .purple)

                if !(viewModel.absentToday.isEmpty && viewModel.leftEarlyToday.isEmpty) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(StringSorting.sortByLocalizedCaseInsensitive(items: viewModel.absentToday, extractor: { displayNameForID($0) }), id: \.self) { sid in
                                let name = displayNameForID(sid)
                                if !name.trimmed().isEmpty {
                                    studentPill(name, color: .red)
                                        .contextMenu {
                                            Text(name)
                                            Divider()
                                            Button {
                                                markTardy(sid)
                                            } label: {
                                                Label("Mark Tardy", systemImage: "clock")
                                            }
                                        }
                                }
                            }
                            if !viewModel.absentToday.isEmpty && !viewModel.leftEarlyToday.isEmpty {
                                Color.clear.frame(width: 8)
                            }
                            ForEach(StringSorting.sortByLocalizedCaseInsensitive(items: viewModel.leftEarlyToday, extractor: { displayNameForID($0) }), id: \.self) { sid in
                                let name = displayNameForID(sid)
                                if !name.trimmed().isEmpty {
                                    studentPill(name, color: .purple)
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
                
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isAttendanceExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Attendance Actions
    private func markTardy(_ studentID: UUID) {
        let (day, _) = AppCalendar.dayRange(for: viewModel.date)
        let store = AttendanceStore(context: modelContext, calendar: calendar)
        
        do {
            var descriptor = FetchDescriptor<AttendanceRecord>(
                predicate: #Predicate { rec in
                    rec.studentID == studentID.uuidString && rec.date == day
                }
            )
            descriptor.fetchLimit = 1
            
            let records = try modelContext.fetch(descriptor)
            if let record = records.first {
                // Update existing record
                store.updateStatus(record, to: .tardy)
            } else {
                // Create new record if it doesn't exist
                guard viewModel.studentsByID[studentID] != nil else { return }
                let record = AttendanceRecord(studentID: studentID, date: day, status: .tardy)
                modelContext.insert(record)
            }
            
            // Save changes
            try modelContext.save()
            
            // Reload the view model to reflect changes
            viewModel.reload()
        } catch {
            print("Error updating attendance status: \(error.localizedDescription)")
        }
    }
    
    private func updateAttendanceStatus(for studentID: UUID, to status: AttendanceStatus) {
        let store = AttendanceStore(context: modelContext, calendar: calendar)
        let day = AppCalendar.startOfDay(viewModel.date)
        
        // Fetch or create the attendance record
        do {
            var descriptor = FetchDescriptor<AttendanceRecord>(
                predicate: #Predicate { rec in
                    rec.studentID == studentID.uuidString && rec.date == day
                }
            )
            descriptor.fetchLimit = 1
            
            let records = try modelContext.fetch(descriptor)
            if let record = records.first {
                // Update existing record
                store.updateStatus(record, to: status)
            } else {
                // Create new record if it doesn't exist
                // Verify student exists (should be in studentsByID cache)
                guard viewModel.studentsByID[studentID] != nil else {
                    print("Warning: Cannot update attendance for student \(studentID) - student not found")
                    return
                }
                let record = AttendanceRecord(studentID: studentID, date: day, status: status)
                modelContext.insert(record)
            }
            
            // Save changes
            try modelContext.save()
            
            // Reload the view model to reflect changes
            viewModel.reload()
        } catch {
            print("Error updating attendance status: \(error.localizedDescription)")
        }
    }

    private func statChip(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(title) \(count)")
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().strokeBorder(color.opacity(0.20), lineWidth: 1))
    }

    // MARK: - List Sections (for List view)
    
    private var remindersListSection: some View {
        Section {
            if viewModel.overdueReminders.isEmpty && viewModel.todaysReminders.isEmpty {
                ContentUnavailableView("No reminders", systemImage: "bell.slash")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if !viewModel.overdueReminders.isEmpty {
                    ForEach(viewModel.overdueReminders) { reminder in
                        ReminderListRow(reminder: reminder, onToggle: { toggleReminder(reminder) })
                            .swipeActions(edge: .leading) {
                                Button {
                                    toggleReminder(reminder)
                                } label: {
                                    Label("Complete", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                    }
                }
                if !viewModel.todaysReminders.isEmpty {
                    ForEach(viewModel.todaysReminders) { reminder in
                        ReminderListRow(reminder: reminder, onToggle: { toggleReminder(reminder) })
                            .swipeActions(edge: .leading) {
                                Button {
                                    toggleReminder(reminder)
                                } label: {
                                    Label("Complete", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                    }
                }
            }
        } header: {
            Label("Reminders", systemImage: "bell.fill")
        }
    }
    
    private func toggleReminder(_ reminder: Reminder) {
        if reminder.isCompleted {
            reminder.markIncomplete()
        } else {
            reminder.markCompleted()
        }
        do {
            try modelContext.save()
            viewModel.reload()
        } catch {
            print("Error toggling reminder: \(error)")
        }
    }
    
    private var lessonsListSection: some View {
        Section {
            if viewModel.todaysLessons.isEmpty {
                ContentUnavailableView("No lessons scheduled today", systemImage: "calendar")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.todaysLessons, id: \.id) { sl in
                    LessonListRow(
                        lessonName: nameForLesson(sl.resolvedLessonID),
                        studentNames: studentNamesForIDs(sl.resolvedStudentIDs),
                        isPresented: sl.isPresented
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedStudentLesson = sl
                    }
                }
            }
        } header: {
            Label("Lessons for Today", systemImage: "text.book.closed")
        }
    }
    
    private var checkInsListSection: some View {
        Section {
            if viewModel.overdueSchedule.isEmpty && viewModel.todaysSchedule.isEmpty {
                ContentUnavailableView("No check-ins due", systemImage: "checkmark.circle")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if !viewModel.overdueSchedule.isEmpty {
                    ForEach(viewModel.overdueSchedule) { item in
                        ContractScheduleListRow(item: item,
                                              studentName: resolveStudentName(for: item.work),
                                              lessonName: resolveLessonName(for: item.work),
                                              onTap: {
                            selectedWorkID = item.work.id
                        })
                    }
                }
                if !viewModel.todaysSchedule.isEmpty {
                    ForEach(viewModel.todaysSchedule) { item in
                        ContractScheduleListRow(item: item,
                                              studentName: resolveStudentName(for: item.work),
                                              lessonName: resolveLessonName(for: item.work),
                                              onTap: {
                            selectedWorkID = item.work.id
                        })
                    }
                }
            }
        } header: {
            Label("Scheduled Check-Ins", systemImage: "bell")
        }
    }
    
    private var inProgressListSection: some View {
        Section {
            if viewModel.staleFollowUps.isEmpty {
                ContentUnavailableView("No follow-ups due", systemImage: "checkmark.circle")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.staleFollowUps) { item in
                    ContractFollowUpListRow(item: item,
                                          studentName: resolveStudentName(for: item.work),
                                          lessonName: resolveLessonName(for: item.work),
                                          onTap: {
                        selectedWorkID = item.work.id
                    })
                }
            }
        } header: {
            Label("Follow-Ups Due", systemImage: "bolt")
        }
    }
    
    private var completedListSection: some View {
        Section {
            if viewModel.completedContracts.isEmpty {
                ContentUnavailableView("No completions yet", systemImage: "clock")
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.completedContracts) { work in
                    CompletionListRow(
                        studentName: resolveStudentName(for: work),
                        lessonName: resolveLessonName(for: work),
                        work: work
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedWorkID = work.id
                    }
                }
            }
        } header: {
            Label("Completed Today", systemImage: "checkmark.circle")
        }
    }
    
    // MARK: - Helpers
    private func resolveStudentName(for work: WorkModel) -> String {
        guard let uuid = UUID(uuidString: work.studentID) else { return "Student" }
        return displayNameForID(uuid)
    }
    
    private func resolveLessonName(for work: WorkModel) -> String {
        guard let uuid = UUID(uuidString: work.lessonID) else { return "Lesson" }
        return nameForLesson(uuid)
    }
}

// MARK: - Attendance Expanded View Logic
private struct AttendanceExpandedView: View {
    let date: Date
    let isNonSchoolDay: Bool
    let onChange: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    
    @Query(sort: [SortDescriptor(\Student.lastName), SortDescriptor(\Student.firstName)])
    private var allStudents: [Student]
    
    @StateObject private var viewModel = AttendanceViewModel()
    
    @SyncedAppStorage("AttendanceEmail.enabled") private var emailEnabled: Bool = true
    @State private var showMailSheet = false
    @State private var toastMessage: String? = nil
    @State private var isEditing: Bool = true
    @State private var localSortKey: AttendanceViewModel.SortKey = .lastName
    
    // Persistence for locking
    private static let lockKeyPrefix = "Attendance.locked."
    private static let lockDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = .current
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    private let syncedStore = SyncedPreferencesStore.shared
    
    private func lockKey(for date: Date) -> String {
        let day = AppCalendar.startOfDay(date)
        let s = AttendanceExpandedView.lockDateFormatter.string(from: day)
        return AttendanceExpandedView.lockKeyPrefix + s
    }
    
    private func isLocked(for date: Date) -> Bool {
        syncedStore.bool(forKey: lockKey(for: date))
    }
    
    private func setLocked(_ locked: Bool, for date: Date) {
        let key = lockKey(for: date)
        if locked {
            syncedStore.set(true, forKey: key)
        } else {
            syncedStore.remove(key: key)
        }
    }
    
    private var filteredStudents: [Student] {
        let visible = viewModel.visibleStudents(from: allStudents)
        return viewModel.sortedAndFiltered(students: visible)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            // Action Bar
            HStack(spacing: 12) {
                // Sort
                Picker("Sort", selection: $localSortKey) {
                    Text("First").tag(AttendanceViewModel.SortKey.firstName)
                    Text("Last").tag(AttendanceViewModel.SortKey.lastName)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                
                Spacer()
                
                // Lock
                Button {
                    isEditing.toggle()
                    setLocked(!isEditing, for: date)
                } label: {
                    Label(isEditing ? "Lock" : "Unlock", systemImage: isEditing ? "lock.fill" : "lock.open")
                }
                .buttonStyle(.bordered)
                .help(isEditing ? "Lock this day" : "Unlock this day")
                
                // Reset
                Button {
                    viewModel.resetDay(students: filteredStudents, modelContext: modelContext)
                    _ = saveCoordinator.save(modelContext, reason: "Reset day")
                    onChange()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isNonSchoolDay || !isEditing)
                .help("Reset Day")
                
                // Mark All Present
                Button("Mark All Present") {
                    viewModel.markAllPresent(students: filteredStudents, modelContext: modelContext)
                    _ = saveCoordinator.save(modelContext, reason: "Mark all present")
                    onChange()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isNonSchoolDay || !isEditing)
                
                // Email
                if emailEnabled {
                    Button {
                        prepareAttendanceEmail()
                    } label: {
                        Label("Email", systemImage: "envelope")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isNonSchoolDay)
                }
            }
            .padding(.vertical, 10)
            
            // Grid
            if isNonSchoolDay {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("Non-school day. Attendance optional.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
            
            AttendanceGrid(
                students: filteredStudents,
                recordsByStudent: viewModel.recordsByStudent,
                onCycleStatus: { student in
                    viewModel.cycleStatus(for: student, modelContext: modelContext)
                    _ = saveCoordinator.save(modelContext, reason: "Update status")
                    onChange()
                },
                onUpdateNote: { student, note in
                    viewModel.updateNote(for: student, note: note, modelContext: modelContext)
                    _ = saveCoordinator.save(modelContext, reason: "Update note")
                },
                onUpdateAbsenceReason: { student, reason in
                    viewModel.updateAbsenceReason(for: student, reason: reason, modelContext: modelContext)
                    _ = saveCoordinator.save(modelContext, reason: "Update reason")
                }
            )
            .frame(height: 700) // Increased height to ensure more students are visible
        }
        .onAppear {
            loadData()
        }
        .onChange(of: date) { _, _ in
            loadData()
        }
        .onChange(of: allStudents.map { $0.id }) { _, _ in
            loadData()
        }
        .onChange(of: localSortKey) { _, newValue in
            DispatchQueue.main.async {
                viewModel.sortKey = newValue
            }
        }
        .sheet(isPresented: $showMailSheet) {
#if os(iOS)
            AttendanceEmail.composerForCurrentPrefs(
                present: names(for: .present),
                tardy: names(for: .tardy),
                absent: names(for: .absent),
                date: date
            ) { result, error in
                // Handle result if needed
            }
            .ignoresSafeArea()
#endif
        }
    }
    
    private func loadData() {
        viewModel.load(for: date, students: viewModel.visibleStudents(from: allStudents), modelContext: modelContext)
        isEditing = !isLocked(for: date)
        localSortKey = viewModel.sortKey
    }
    
    private func names(for status: AttendanceStatus) -> [String] {
        filteredStudents.compactMap { s in
            if let rec = viewModel.recordsByStudent[s.id.uuidString], rec.status == status {
                return s.fullName
            }
            return nil
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    private func prepareAttendanceEmail() {
        let present = names(for: .present)
        let tardy = names(for: .tardy)
        let absent = names(for: .absent)
#if os(iOS)
        if MFMailComposeViewController.canSendMail() {
            showMailSheet = true
        }
#else
        AttendanceEmail.sendUsingMailAppForCurrentPrefs(
            present: present,
            tardy: tardy,
            absent: absent,
            date: date
        ) { _ in }
#endif
    }
}

// MARK: - Rows

private struct ContractScheduleRow: View {
    let item: ContractScheduleItem
    let studentName: String
    let lessonName: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: item.planItem.reason?.icon ?? "bell").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studentName)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Text(item.planItem.reason?.label ?? "Check-In")
                        if let note = item.planItem.note, !note.isEmpty {
                            Text("• \(note)")
                        }
                    }
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.planItem.scheduledDate, style: .date)
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }
}

private struct ContractFollowUpRow: View {
    let item: ContractFollowUpItem
    let studentName: String
    let lessonName: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise").foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studentName)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(item.daysSinceTouch) days since update")
                        .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }
}

private struct TodayLessonRow: View {
    let lessonName: String
    let studentNames: String
    let isPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.book.closed").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                if !studentNames.trimmed().isEmpty {
                    Text(studentNames)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Text(lessonName)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isPresented {
                Text("Presented")
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}

private struct CompletionRow: View {
    let studentName: String
    let lessonName: String
    let work: WorkModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(studentName)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(lessonName)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !work.notes.trimmed().isEmpty || (work.unifiedNotes?.isEmpty == false) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}

private struct ReminderRow: View {
    let reminder: Reminder
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reminder.isCompleted ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .strikethrough(reminder.isCompleted)
                    if let dueDate = reminder.dueDate {
                        Text(dueDate, style: .time)
                            .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if let notes = reminder.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: reminder.isCompleted)
    }
}

// MARK: - List Row Components (for List view)

private struct ReminderListRow: View {
    let reminder: Reminder
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reminder.isCompleted ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .strikethrough(reminder.isCompleted)
                    if let dueDate = reminder.dueDate {
                        Text(dueDate, style: .time)
                            .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if let notes = reminder.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: reminder.isCompleted)
    }
}

private struct LessonListRow: View {
    let lessonName: String
    let studentNames: String
    let isPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.book.closed").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                if !studentNames.trimmed().isEmpty {
                    Text(studentNames)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Text(lessonName)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isPresented {
                Text("Presented")
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            }
        }
    }
}

private struct ContractScheduleListRow: View {
    let item: ContractScheduleItem
    let studentName: String
    let lessonName: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: item.planItem.reason?.icon ?? "bell").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studentName)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Text(item.planItem.reason?.label ?? "Check-In")
                        if let note = item.planItem.note, !note.isEmpty {
                            Text("• \(note)")
                        }
                    }
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.planItem.scheduledDate, style: .date)
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ContractFollowUpListRow: View {
    let item: ContractFollowUpItem
    let studentName: String
    let lessonName: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise").foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studentName)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(lessonName)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(item.daysSinceTouch) days since update")
                        .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CompletionListRow: View {
    let studentName: String
    let lessonName: String
    let work: WorkModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(studentName)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(lessonName)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !work.notes.trimmed().isEmpty || (work.unifiedNotes?.isEmpty == false) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
