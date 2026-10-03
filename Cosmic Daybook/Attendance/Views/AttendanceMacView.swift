// AttendanceMacView.swift
// The Mac and iPad Attendance screen: the day in the toolbar, the roll (its
// band and tiles), and Insights beside it with the month.

import SwiftUI
import CoreData
import OSLog

struct AttendanceMacView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(RestoreCoordinator.self) private var restoreCoordinator
    @Environment(\.dependencies) private var dependencies

    // Active on the selected day, not enrolled-only: browsing a past date shows the
    // roster as it was then, so former students' attendance stays visible and editable.
    private var students: [CDStudent] {
        let day = AppCalendar.startOfDay(selectedDate)
        let nextDay = AppCalendar.shared.date(byAdding: .day, value: 1, to: day) ?? day
        return dependencies.roster.all.filterActive(in: DateRange(start: day, end: nextDay))
    }

    @State private var selectedDate: Date = AppCalendar.startOfDay(Date())
    /// The school day that stood for today when the screen last looked; see
    /// `AttendanceDayRollover`.
    @State private var todayAnchor: Date?
    @State private var visibleMonth: Date = AppCalendar.startOfDay(Date())
    @State private var monthCounts: [Date: DayAttendanceCounts] = [:]
    @State private var historySheetStudentID: UUID?
    @State private var reloadToken: Int = 0
    /// The pending refresh of the month and Insights after marks.
    @State private var refreshTask: Task<Void, Never>?
    @State private var toastMessage: String?
    /// "Day 37", from the roll (`AttendanceDayLabelKey`).
    @State private var dayLabel: String?
    @State private var showingDatePicker = false

    private static let logger = Logger.attendance

    var body: some View {
        Group {
            if restoreCoordinator.isRestoring {
                restoringView
            } else {
                mainContent
            }
        }
        .onAppear {
            ensureSelectedIsSchoolDay()
            handleDayChange()
            reloadMonthCounts()
        }
        // Left open overnight on today, the roll moves to the new today.
        .onCalendarDayChange {
            handleDayChange()
        }
        // A new day in the same month needs no new counts, and Insights
        // follows the day itself; a new month reads its counts once.
        .onChange(of: visibleMonth) { _, _ in
            reloadMonthCounts()
        }
        // Keeps the month and Insights current when another device marks.
        .onPresentationDataChangeWhenVisible(
            of: ["AttendanceRecord"], in: viewContext, catchUpOnAppear: false
        ) {
            scheduleRefresh()
        }
        .onDisappear { refreshTask?.cancel() }
        .sheet(item: Binding(
            get: { historySheetStudentID.map { StudentIDBox(id: $0) } },
            set: { historySheetStudentID = $0?.id }
        )) { box in
            AttendanceStudentHistorySheet(studentID: box.id)
        }
        .toastBanner(toastMessage)
    }

    // MARK: Layout

    private var mainContent: some View {
        HStack(alignment: .top, spacing: 0) {
            mainColumn
                .frame(maxWidth: .infinity)

            Divider()

            AttendanceInsightsSidebar(
                students: students,
                referenceDate: selectedDate,
                reloadToken: reloadToken,
                month: AttendanceSidebarMonth(
                    visibleMonth: visibleMonth,
                    counts: monthCounts,
                    onChangeMonth: { visibleMonth = $0 }
                ),
                onSelectStudent: { studentID in historySheetStudentID = studentID },
                onSelectDate: { date in selectDate(date) }
            )
        }
        .navigationTitle("Attendance")
        .navigationSubtitle(dayLabel ?? "")
        .toolbar { dayNavigation }
        .onPreferenceChange(AttendanceDayLabelKey.self) { dayLabel = $0 }
    }

    private var mainColumn: some View {
        AttendanceExpandedView(
            date: selectedDate,
            isNonSchoolDay: SchoolCalendarService.shared.isNonSchoolDaySync(selectedDate, using: viewContext),
            onChange: { scheduleRefresh() },
            onToast: { message in toast(message) },
            showsDayInTitle: true,
            hostsToolbar: true
        )
        .padding(.horizontal, AppTheme.Spacing.large)
    }

    // MARK: Day navigation

    /// ‹ Wednesday, Sep 23 › and Today, in the toolbar: the day appears
    /// once. The date opens a calendar; the arrows step through school days.
    @ToolbarContentBuilder
    private var dayNavigation: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Previous School Day", systemImage: "chevron.left") {
                selectDate(previousSchoolDay(before: selectedDate))
            }
            .help("Previous school day")
            Button {
                showingDatePicker = true
            } label: {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .fontWeight(.semibold)
                    .fixedSize()
            }
            .help("Go to a day")
            .popover(isPresented: $showingDatePicker, arrowEdge: .bottom) { datePopover }
            Button("Next School Day", systemImage: "chevron.right") {
                selectDate(nextSchoolDay(after: selectedDate))
            }
            .help("Next school day")
            Button("Today") { selectDate(nearestSchoolDay(to: Date())) }
                .disabled(AppCalendar.isSameDay(selectedDate, nearestSchoolDay(to: Date())))
                .help("Jump to today")
        }
    }

    private var datePopover: some View {
        DatePicker(
            "Day",
            selection: Binding(
                get: { selectedDate },
                set: { newValue in
                    selectDate(nearestSchoolDay(to: newValue))
                    showingDatePicker = false
                }
            ),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding()
    }

    // MARK: Restoring + Toast

    private var restoringView: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            ProgressView().controlSize(.large)
            Text("Restoring data…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toast(_ message: String) {
        showToast(message, in: $toastMessage, logger: Self.logger)
    }

    // MARK: Data

    private func reloadMonthCounts() {
        let cal = AppCalendar.shared
        guard let interval = cal.dateInterval(of: .month, for: visibleMonth) else { return }
        let start = AppCalendar.startOfDay(interval.start)
        let endExclusive = AppCalendar.startOfDay(interval.end)
        let endInclusive = cal.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
        monthCounts = AttendanceInsightsService.dayCounts(in: start...endInclusive, context: viewContext)
    }

    /// The month and Insights after marks, once the marking pauses: taking
    /// the roll is a mark every second or two, and each refresh re-reads the
    /// month and the whole Insights window (a year of records on Year).
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            guard (try? await Task.sleep(for: .seconds(1.5))) != nil else { return }
            reloadToken &+= 1
            reloadMonthCounts()
        }
    }

    // MARK: Selection helpers

    private func selectDate(_ date: Date) {
        let day = AppCalendar.startOfDay(date)
        selectedDate = day
        if !AppCalendar.shared.isDate(day, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = day
        }
    }

    private func handleDayChange() {
        let newAnchor = nearestSchoolDay(to: Date())
        let next = AttendanceDayRollover.advance(selected: selectedDate, anchor: todayAnchor, newAnchor: newAnchor)
        todayAnchor = next.anchor
        if next.selected != selectedDate { selectDate(next.selected) }
    }

    private func ensureSelectedIsSchoolDay() {
        let coerced = nearestSchoolDay(to: selectedDate)
        if coerced != selectedDate {
            selectDate(coerced)
        }
    }

    // MARK: School day navigation

    private func previousSchoolDay(before date: Date) -> Date {
        SchoolCalendarService.shared.previousSchoolDaySync(before: date, using: viewContext)
    }

    private func nextSchoolDay(after date: Date) -> Date {
        SchoolCalendarService.shared.nextSchoolDaySync(after: date, using: viewContext)
    }

    /// Kept local rather than using `SchoolCalendarService.nearestSchoolDaySync`:
    /// this screen resolves a tie toward the *previous* school day, where the
    /// shared helper prefers the next one.
    private func nearestSchoolDay(to date: Date) -> Date {
        let day = AppCalendar.startOfDay(date)
        if !SchoolCalendarService.shared.isNonSchoolDaySync(day, using: viewContext) { return day }
        let prev = previousSchoolDay(before: day)
        let next = nextSchoolDay(after: day)
        let distPrev = abs(prev.timeIntervalSince(day))
        let distNext = abs(next.timeIntervalSince(day))
        return distPrev <= distNext ? prev : next
    }
}

private struct StudentIDBox: Identifiable {
    let id: UUID
}
