// AttendanceMonthHeatmap.swift
// Compact month calendar that tints each school day by absence/tardy load.
// Click a day to jump to that day's roll.

import SwiftUI
import CoreData

/// A month calendar with heatmap shading, built around `DayAttendanceCounts` from
/// `AttendanceInsightsService`.
struct AttendanceMonthHeatmap: View {
    let visibleMonth: Date
    let selectedDate: Date
    let counts: [Date: DayAttendanceCounts]
    let isNonSchoolDay: (Date) -> Bool
    let onSelectDate: (Date) -> Void
    let onChangeMonth: (Date) -> Void

    private var monthLabel: String {
        DateFormatters.monthYear.string(from: visibleMonth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            header
            weekdayHeader
            grid
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.compact)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Button {
                onChangeMonth(addMonths(-1, to: visibleMonth))
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Previous month")

            Text(monthLabel)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .frame(minWidth: 130, alignment: .center)

            Button {
                onChangeMonth(addMonths(1, to: visibleMonth))
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Next month")

            Spacer()

            heatLegend
        }
    }

    private var heatLegend: some View {
        HStack(spacing: 4) {
            Text("Absences")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(absenceTint(forIntensity: Double(idx) / 4.0))
                    .frame(width: 10, height: 10)
            }
        }
    }

    // MARK: Weekday header

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdaySymbols: [String] {
        // Ordered to match the calendar's firstWeekday.
        let cal = AppCalendar.shared
        let symbols = cal.veryShortStandaloneWeekdaySymbols // Sun, Mon, ...
        let firstIdx = cal.firstWeekday - 1
        let rotated = Array(symbols[firstIdx...]) + Array(symbols[..<firstIdx])
        return rotated
    }

    // MARK: Grid

    private var grid: some View {
        let weeks = monthWeeks(for: visibleMonth)
        return VStack(spacing: 4) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(week, id: \.self) { day in
                        cell(for: day)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for day: Date) -> some View {
        let inMonth = AppCalendar.shared.isDate(day, equalTo: visibleMonth, toGranularity: .month)
        let isSelected = AppCalendar.isSameDay(day, selectedDate)
        let isToday = AppCalendar.isSameDay(day, Date())
        let nonSchool = isNonSchoolDay(day)
        let dayCount = counts[AppCalendar.startOfDay(day)] ?? DayAttendanceCounts()

        Button {
            onSelectDate(AppCalendar.startOfDay(day))
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(cellFill(dayCount: dayCount, inMonth: inMonth, nonSchool: nonSchool))

                if dayCount.tardy > 0 && !nonSchool {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.55), lineWidth: 1.2)
                }

                if isSelected {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }

                Text(dayNumber(for: day))
                    .font(.system(size: 11, weight: isToday ? .bold : .regular, design: .rounded))
                    .foregroundStyle(textColor(inMonth: inMonth, nonSchool: nonSchool))
            }
            .frame(height: 28)
            .opacity(inMonth ? 1.0 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!inMonth)
        .help(helpText(for: day, dayCount: dayCount, nonSchool: nonSchool))
    }

    private func cellFill(dayCount: DayAttendanceCounts, inMonth: Bool, nonSchool: Bool) -> Color {
        if !inMonth {
            return Color.gray.opacity(0.05)
        }
        if nonSchool {
            return Color.gray.opacity(0.10)
        }
        let absent = dayCount.absent + dayCount.leftEarly
        guard absent > 0 else {
            return Color.green.opacity(0.10)
        }
        // Cap intensity at 5 absences for the gradient.
        let intensity = min(Double(absent) / 5.0, 1.0)
        return absenceTint(forIntensity: intensity)
    }

    private func absenceTint(forIntensity intensity: Double) -> Color {
        // Light red → deep red.
        let clamped = max(0.05, min(intensity, 1.0))
        let opacity = 0.10 + clamped * 0.55
        return Color.red.opacity(opacity)
    }

    private func textColor(inMonth: Bool, nonSchool: Bool) -> Color {
        if !inMonth { return .secondary }
        if nonSchool { return .secondary.opacity(0.6) }
        return .primary
    }

    private func dayNumber(for day: Date) -> String {
        let comp = AppCalendar.shared.component(.day, from: day)
        return "\(comp)"
    }

    private func helpText(for day: Date, dayCount: DayAttendanceCounts, nonSchool: Bool) -> String {
        let dateLabel = DateFormatters.fullDate.string(from: day)
        if nonSchool { return "\(dateLabel) — non-school day" }
        if !dayCount.hasAnyMarked { return "\(dateLabel) — no attendance recorded" }
        var parts: [String] = []
        if dayCount.present > 0 { parts.append("\(dayCount.present) present") }
        if dayCount.tardy > 0 { parts.append("\(dayCount.tardy) tardy") }
        if dayCount.absent > 0 { parts.append("\(dayCount.absent) absent") }
        if dayCount.leftEarly > 0 { parts.append("\(dayCount.leftEarly) left early") }
        return "\(dateLabel) — " + parts.joined(separator: ", ")
    }

    // MARK: Date math

    private func addMonths(_ months: Int, to date: Date) -> Date {
        AppCalendar.shared.date(byAdding: .month, value: months, to: date) ?? date
    }

    /// Returns calendar weeks of the month, padded with leading/trailing days from neighboring months
    /// so every week is a full 7 cells.
    private func monthWeeks(for date: Date) -> [[Date]] {
        let cal = AppCalendar.shared
        guard let monthInterval = cal.dateInterval(of: .month, for: date) else { return [] }
        let firstOfMonth = monthInterval.start

        // Step back to the start of the week containing the first of the month.
        let firstWeekday = cal.firstWeekday
        let weekday = cal.component(.weekday, from: firstOfMonth)
        let leadingOffset = (weekday - firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -leadingOffset, to: firstOfMonth) else { return [] }

        // Always show 6 weeks for layout stability.
        var weeks: [[Date]] = []
        for week in 0..<6 {
            var row: [Date] = []
            for dayOffset in 0..<7 {
                let offset = week * 7 + dayOffset
                if let day = cal.date(byAdding: .day, value: offset, to: gridStart) {
                    row.append(AppCalendar.startOfDay(day))
                }
            }
            weeks.append(row)
        }
        return weeks
    }
}
