// AttendanceMonthHeatmap.swift
// The Insights month: school weeks Monday to Friday, each day tinted by its
// absences, with a dot for late arrivals. Click a day to open its roll.

import SwiftUI
import CoreData

/// A compact month of weekdays for the Insights column, built around
/// `DayAttendanceCounts` from `AttendanceInsightsService`. Weekends aren't
/// drawn (no school), and days outside the month are left blank.
struct AttendanceMonthHeatmap: View {
    let visibleMonth: Date
    let selectedDate: Date
    let counts: [Date: DayAttendanceCounts]
    let isNonSchoolDay: (Date) -> Bool
    let onSelectDate: (Date) -> Void
    let onChangeMonth: (Date) -> Void

    private static let weekdaySymbols = ["M", "T", "W", "T", "F"]
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            header
            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(Self.weekdaySymbols.indices, id: \.self) { index in
                    Text(Self.weekdaySymbols[index])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(weekdayCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(for: day)
                    } else {
                        Color.clear.frame(height: 26)
                    }
                }
            }
            Text("Tint shows absences · a dot shows late arrivals")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.control, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Spacer()
            Button("Previous Month", systemImage: "chevron.left") {
                onChangeMonth(addMonths(-1, to: visibleMonth))
            }
            Button("Next Month", systemImage: "chevron.right") {
                onChangeMonth(addMonths(1, to: visibleMonth))
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    // MARK: Cells

    private func cell(for day: Date) -> some View {
        let isSelected = AppCalendar.isSameDay(day, selectedDate)
        let isToday = AppCalendar.isSameDay(day, Date())
        let nonSchool = isNonSchoolDay(day)
        let dayCount = counts[AppCalendar.startOfDay(day)] ?? DayAttendanceCounts()

        return Button {
            onSelectDate(AppCalendar.startOfDay(day))
        } label: {
            Text(dayNumber(for: day))
                .font(.system(size: 11, weight: isToday || isSelected ? .bold : .regular, design: .rounded))
                .foregroundStyle(nonSchool ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(cellFill(dayCount: dayCount, nonSchool: nonSchool, day: day))
                )
                .overlay(alignment: .topTrailing) {
                    if dayCount.tardy > 0 && !nonSchool {
                        Circle().fill(Color.lateAmber).frame(width: 5, height: 5).padding(3)
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText(for: day, dayCount: dayCount, nonSchool: nonSchool))
        .accessibilityLabel(helpText(for: day, dayCount: dayCount, nonSchool: nonSchool))
    }

    private func cellFill(dayCount: DayAttendanceCounts, nonSchool: Bool, day: Date) -> Color {
        if nonSchool { return Color.secondary.opacity(0.05) }
        guard dayCount.hasAnyMarked else {
            return day > Date() ? Color.clear : Color.secondary.opacity(0.08)
        }
        let absent = dayCount.absent
        guard absent > 0 else { return Color.green.opacity(0.12) }
        // Light red to deep red, capped at five absences.
        let intensity = min(Double(absent) / 5.0, 1.0)
        return Color.red.opacity(0.12 + intensity * 0.5)
    }

    private func dayNumber(for day: Date) -> String {
        "\(AppCalendar.shared.component(.day, from: day))"
    }

    private func helpText(for day: Date, dayCount: DayAttendanceCounts, nonSchool: Bool) -> String {
        let dateLabel = DateFormatters.fullDate.string(from: day)
        if nonSchool { return "\(dateLabel): no school" }
        if !dayCount.hasAnyMarked { return "\(dateLabel): no attendance recorded" }
        var parts: [String] = []
        if dayCount.present > 0 { parts.append("\(dayCount.present) present") }
        if dayCount.tardy > 0 { parts.append("\(dayCount.tardy) late") }
        if dayCount.absent > 0 { parts.append("\(dayCount.absent) absent") }
        if dayCount.leftEarly > 0 { parts.append("\(dayCount.leftEarly) left early") }
        return "\(dateLabel): " + parts.joined(separator: ", ")
    }

    // MARK: Date math

    private func addMonths(_ months: Int, to date: Date) -> Date {
        AppCalendar.shared.date(byAdding: .month, value: months, to: date) ?? date
    }

    /// The month's weekdays in Monday-to-Friday rows, with nil for the
    /// days of the first and last rows that fall outside the month.
    private var weekdayCells: [Date?] {
        let cal = AppCalendar.shared
        guard let interval = cal.dateInterval(of: .month, for: visibleMonth),
              let lastDay = cal.date(byAdding: .day, value: -1, to: interval.end) else { return [] }
        var cells: [Date?] = []
        var day = AppCalendar.startOfDay(interval.start)
        // Monday is weekday 2; pad the first row up to the month's first weekday.
        let firstWeekday = cal.component(.weekday, from: day)
        if (2...6).contains(firstWeekday) {
            cells += Array(repeating: nil, count: firstWeekday - 2)
        }
        while day <= lastDay {
            if (2...6).contains(cal.component(.weekday, from: day)) { cells.append(day) }
            day = AppCalendar.addingDays(1, to: day)
        }
        return cells
    }
}
