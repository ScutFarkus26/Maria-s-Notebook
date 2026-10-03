// AttendanceStandaloneView.swift
// Standalone attendance view for iPhone compact layout.
// Shows only attendance functionality without the Today view's other sections.

import SwiftUI
import CoreData
import OSLog

/// Standalone attendance view for iPhone that displays just the attendance grid
/// without the Today view's reminders, lessons, and other sections.
struct AttendanceStandaloneView: View {
    private static let logger = Logger.attendance

    // MARK: - Environment
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.calendar) var calendar
    @Environment(RestoreCoordinator.self) var restoreCoordinator

    // MARK: - State
    @State private var date: Date = AppCalendar.startOfDay(Date())
    /// The school-day-coerced date that currently represents "today". When the
    /// calendar day changes we only auto-advance `date` if it still equals this
    /// anchor — a deliberately chosen date is kept.
    @State private var todayAnchor: Date?
    @State private var toastMessage: String?
    /// "Day 37", from the roll (`AttendanceDayLabelKey`).
    @State private var dayLabel: String?

    // MARK: - Body
    var body: some View {
        Group {
            if restoreCoordinator.isRestoring {
                restoringView
            } else {
                mainContent
            }
        }
        .onAppear {
            let coerced = nearestSchoolDaySync(to: date)
            if coerced != date {
                date = AppCalendar.startOfDay(coerced)
            }
            if todayAnchor == nil {
                todayAnchor = AppCalendar.startOfDay(coerced)
            }
            handleDayChange()
        }
        .onCalendarDayChange {
            handleDayChange()
        }
        .toastBanner(toastMessage)
    }

    // MARK: - View Components

    private var restoringView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ProgressView().controlSize(.large)
            Text("Restoring your backup…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainContent: some View {
        NavigationStack {
            AttendanceExpandedView(
                date: date,
                isNonSchoolDay: isNonSchoolDaySync(date),
                onChange: { },
                onToast: { message in toast(message) },
                onStepDay: { forward in
                    let next = forward ? nextSchoolDaySync(after: date) : previousSchoolDaySync(before: date)
                    date = AppCalendar.startOfDay(next)
                },
                showsDayInTitle: true
            )
            .padding(.horizontal, AppTheme.Spacing.compact)
            .quickCaptureButtonClearance()
            .navigationTitle("Attendance")
            .onPreferenceChange(AttendanceDayLabelKey.self) { dayLabel = $0 }
            #if os(iOS)
            .toolbar { toolbarContent }
            #endif
        }
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: AppTheme.Spacing.small) {
                Button {
                    let prev = previousSchoolDaySync(before: date)
                    date = AppCalendar.startOfDay(prev)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                }

                DatePicker("Date", selection: Binding(get: { date }, set: { newValue in
                    let coerced = nearestSchoolDaySync(to: newValue)
                    date = AppCalendar.startOfDay(coerced)
                }), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()

                Button {
                    let next = nextSchoolDaySync(after: date)
                    date = AppCalendar.startOfDay(next)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            // "Day 37" under the date, as the Daybook Assistant shows it.
            .overlay(alignment: .bottom) {
                if let dayLabel {
                    Text(dayLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(y: 16)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Today") {
                let today = Date()
                let coerced = nearestSchoolDaySync(to: today)
                date = AppCalendar.startOfDay(coerced)
            }
            .font(AppTheme.ScaledFont.captionSemibold)
        }
    }
    #endif

    // MARK: - Day Rollover

    /// Rolls `date` forward when the calendar day changes so "Mark N Present"
    /// never overwrites a previous day's records after an overnight suspension.
    /// Idempotent — called at midnight, on scene activation, and on appear.
    private func handleDayChange() {
        let newAnchor = AppCalendar.startOfDay(nearestSchoolDaySync(to: Date()))
        let next = AttendanceDayRollover.advance(selected: date, anchor: todayAnchor, newAnchor: newAnchor)
        if next.selected != date { date = next.selected }
        todayAnchor = next.anchor
    }

    // MARK: - School Day Navigation
    // Thin wrappers over the shared school-day cache.

    private func isNonSchoolDaySync(_ date: Date) -> Bool {
        SchoolCalendarService.shared.isNonSchoolDaySync(date, using: viewContext)
    }

    private func nextSchoolDaySync(after date: Date) -> Date {
        SchoolCalendarService.shared.nextSchoolDaySync(after: date, using: viewContext)
    }

    private func previousSchoolDaySync(before date: Date) -> Date {
        SchoolCalendarService.shared.previousSchoolDaySync(before: date, using: viewContext)
    }

    private func nearestSchoolDaySync(to date: Date) -> Date {
        SchoolCalendarService.shared.nearestSchoolDaySync(to: date, using: viewContext)
    }

    // MARK: - Toast

    private func toast(_ message: String) {
        showToast(message, in: $toastMessage, logger: Self.logger)
    }
}
