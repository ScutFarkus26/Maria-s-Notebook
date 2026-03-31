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
    @State private var schoolDayCache = SchoolDayCache()
    @State private var toastMessage: String?
    @State private var showingTardyReport = false

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
            AppCalendar.adopt(timeZoneFrom: calendar)
            let coerced = nearestSchoolDaySync(to: date)
            if coerced != date {
                date = AppCalendar.startOfDay(coerced)
            }
        }
        .onChange(of: calendar) { _, newCal in
            AppCalendar.adopt(timeZoneFrom: newCal)
        }
        .overlay(alignment: .top) {
            toastOverlay
        }
    }

    // MARK: - View Components

    private var restoringView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ProgressView().controlSize(.large)
            Text("Restoring data…")
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
                onToast: { message in toast(message) }
            )
            .padding(.horizontal, AppTheme.Spacing.compact)
            .navigationTitle("Attendance")
            #if os(iOS)
            .toolbar { toolbarContent }
            #endif
            .sheet(isPresented: $showingTardyReport) {
                AttendanceTardyReport()
            }
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

    // MARK: - School Day Navigation

    private func isNonSchoolDaySync(_ date: Date) -> Bool {
        schoolDayCache.cacheSchoolDayData(for: date, viewContext: viewContext)
        return schoolDayCache.isNonSchoolDay(date)
    }

    private func nextSchoolDaySync(after date: Date) -> Date {
        schoolDayCache.cacheSchoolDayData(for: date, viewContext: viewContext)
        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        for _ in 0..<730 {
            if !schoolDayCache.isNonSchoolDay(d) { return d }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }

    private func previousSchoolDaySync(before date: Date) -> Date {
        schoolDayCache.cacheSchoolDayData(for: date, viewContext: viewContext)
        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        for _ in 0..<730 {
            if !schoolDayCache.isNonSchoolDay(d) { return d }
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }

    private func nearestSchoolDaySync(to date: Date) -> Date {
        schoolDayCache.cacheSchoolDayData(for: date, viewContext: viewContext)
        let day = AppCalendar.startOfDay(date)
        if !schoolDayCache.isNonSchoolDay(day) { return day }
        let prev = previousSchoolDaySync(before: day)
        let next = nextSchoolDaySync(after: day)
        let distPrev = abs(prev.timeIntervalSince(day))
        let distNext = abs(next.timeIntervalSince(day))
        if distPrev < distNext { return prev }
        return next
    }

    // MARK: - Toast

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
}
