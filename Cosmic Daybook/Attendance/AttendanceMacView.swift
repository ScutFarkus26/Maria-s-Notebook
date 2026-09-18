// AttendanceMacView.swift
// Standalone Mac/iPad attendance view that does not inherit TodayView's layout.
// Combines a date header, month heatmap, the existing roll grid, and an insights sidebar.

import SwiftUI
import CoreData
import OSLog

struct AttendanceMacView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar
    @Environment(RestoreCoordinator.self) private var restoreCoordinator

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)])
    private var allStudentsRaw: FetchedResults<CDStudent>
    // Active on the selected day, not enrolled-only: browsing a past date shows the
    // roster as it was then, so former students' attendance stays visible and editable.
    private var students: [CDStudent] {
        let day = AppCalendar.startOfDay(selectedDate)
        let nextDay = AppCalendar.shared.date(byAdding: .day, value: 1, to: day) ?? day
        return Array(allStudentsRaw).uniqueByID.filterActive(in: DateRange(start: day, end: nextDay))
    }

    @State private var selectedDate: Date = AppCalendar.startOfDay(Date())
    @State private var visibleMonth: Date = AppCalendar.startOfDay(Date())
    @State private var monthCounts: [Date: DayAttendanceCounts] = [:]
    @State private var historySheetStudentID: UUID?
    @State private var reloadToken: Int = 0
    @State private var toastMessage: String?

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
            reloadMonthCounts()
        }
        .onChange(of: selectedDate) { _, _ in
            reloadMonthCounts()
            bumpReloadToken()
        }
        .onChange(of: visibleMonth) { _, _ in
            reloadMonthCounts()
        }
        .sheet(item: Binding(
            get: { historySheetStudentID.map { StudentIDBox(id: $0) } },
            set: { historySheetStudentID = $0?.id }
        )) { box in
            AttendanceStudentHistorySheet(studentID: box.id)
        }
        .overlay(alignment: .top) { toastOverlay }
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
                onSelectStudent: { studentID in historySheetStudentID = studentID },
                onSelectDate: { date in selectDate(date) }
            )
        }
        .navigationTitle("Attendance")
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.compact)

            Divider()

            AttendanceMonthHeatmap(
                visibleMonth: visibleMonth,
                selectedDate: selectedDate,
                counts: monthCounts,
                isNonSchoolDay: { SchoolCalendarService.shared.isNonSchoolDaySync($0, using: viewContext) },
                onSelectDate: { date in selectDate(date) },
                onChangeMonth: { month in visibleMonth = month }
            )

            Divider()

            AttendanceExpandedView(
                date: selectedDate,
                isNonSchoolDay: SchoolCalendarService.shared.isNonSchoolDaySync(selectedDate, using: viewContext),
                onChange: { bumpReloadToken() },
                onToast: { message in toast(message) }
            )
            .padding(.horizontal, AppTheme.Spacing.medium)
        }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Button {
                let prev = previousSchoolDay(before: selectedDate)
                selectDate(prev)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Previous school day")

            DatePicker(
                "Date",
                selection: Binding(
                    get: { selectedDate },
                    set: { newValue in
                        let coerced = nearestSchoolDay(to: newValue)
                        selectDate(coerced)
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()

            Button("Today") {
                let today = nearestSchoolDay(to: Date())
                selectDate(today)
            }
            .buttonStyle(.bordered)
            .help("Jump to today")

            Button {
                let next = nextSchoolDay(after: selectedDate)
                selectDate(next)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Next school day")

            Spacer()

            Text(DateFormatters.fullDate.string(from: selectedDate))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
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

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = toastMessage {
            Text(message)
                .font(AppTheme.ScaledFont.captionSemibold)
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.vertical, AppTheme.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                        .fill(Color.black.opacity(UIConstants.OpacityConstants.nearSolid))
                )
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.moderate), radius: 6, x: 0, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
        }
    }

    private func toast(_ message: String) {
        adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            toastMessage = message
        }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2.0))
            } catch {
                Self.logger.warning("Failed to sleep for toast dismissal: \(error)")
            }
            adaptiveWithAnimation(.easeInOut(duration: 0.25)) {
                toastMessage = nil
            }
        }
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

    private func bumpReloadToken() {
        reloadToken &+= 1
        reloadMonthCounts()
    }

    // MARK: Selection helpers

    private func selectDate(_ date: Date) {
        let day = AppCalendar.startOfDay(date)
        selectedDate = day
        if !AppCalendar.shared.isDate(day, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = day
        }
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
