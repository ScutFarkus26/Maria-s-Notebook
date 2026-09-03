// AttendanceStudentHistorySheet.swift
// Modal sheet showing one student's attendance history: 3-month heatmap + notes list.

import SwiftUI
import CoreData
import OSLog

struct AttendanceStudentHistorySheet: View {
    let studentID: UUID

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)])
    private var allStudentsRaw: FetchedResults<CDStudent>

    @State private var records: [CDAttendanceRecord] = []

    private static let logger = Logger.attendance

    private var student: CDStudent? {
        Array(allStudentsRaw).first { $0.id == studentID }
    }

    private var statusByDay: [Date: AttendanceStatus] {
        var map: [Date: AttendanceStatus] = [:]
        for record in records {
            guard let date = record.date else { continue }
            map[AppCalendar.startOfDay(date)] = record.status
        }
        return map
    }

    private var reasonByDay: [Date: AbsenceReason] {
        var map: [Date: AbsenceReason] = [:]
        for record in records {
            guard let date = record.date else { continue }
            map[AppCalendar.startOfDay(date)] = record.absenceReason
        }
        return map
    }

    private var notesEntries: [AttendanceHistoryNoteEntry] {
        records.compactMap { record in
            guard let date = record.date else { return nil }
            let text = record.latestUnifiedNoteText
            guard !text.isEmpty else { return nil }
            return AttendanceHistoryNoteEntry(
                date: AppCalendar.startOfDay(date),
                status: record.status,
                reason: record.absenceReason,
                text: text
            )
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    summaryHeader

                    Text("Last 3 months")
                        .font(.system(.headline, design: .rounded))

                    threeMonthHeatmap

                    if !notesEntries.isEmpty {
                        Text("Notes")
                            .font(.system(.headline, design: .rounded))
                        notesList
                    }

                    Spacer(minLength: 0)
                }
                .padding(AppTheme.Spacing.large)
            }
            .navigationTitle(student?.fullName ?? "Student")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 600)
        #endif
        .onAppear {
            loadRecords()
        }
    }

    // MARK: Summary

    private var summaryHeader: some View {
        let yearTotals = computeYearTotals()
        return HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
            statBlock(
                value: yearTotals.attendanceRate.map(percentString) ?? "—",
                label: "Year attendance",
                tint: .green
            )
            statBlock(
                value: "\(yearTotals.absent)",
                label: yearTotals.absent == 1 ? "Absent" : "Absences",
                tint: .red
            )
            statBlock(
                value: "\(yearTotals.tardy)",
                label: yearTotals.tardy == 1 ? "Tardy" : "Tardies",
                tint: .blue
            )
            if yearTotals.leftEarly > 0 {
                statBlock(
                    value: "\(yearTotals.leftEarly)",
                    label: "Left early",
                    tint: .purple
                )
            }
            Spacer()
        }
    }

    private func statBlock(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 3-month heatmap

    private var threeMonthHeatmap: some View {
        let months = lastThreeMonths()
        return HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
            ForEach(months, id: \.self) { month in
                monthGrid(for: month)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func monthGrid(for month: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DateFormatters.monthYear.string(from: month))
                .font(.caption.weight(.semibold))

            let weeks = monthWeeks(for: month)
            VStack(spacing: 3) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 3) {
                        ForEach(week, id: \.self) { day in
                            dayCell(for: day, monthAnchor: month)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(for day: Date, monthAnchor: Date) -> some View {
        let inMonth = AppCalendar.shared.isDate(day, equalTo: monthAnchor, toGranularity: .month)
        let nonSchool = SchoolCalendarService.shared.isNonSchoolDaySync(day, using: viewContext)
        let status = statusByDay[AppCalendar.startOfDay(day)] ?? .unmarked

        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(cellFill(status: status, inMonth: inMonth, nonSchool: nonSchool))
            Text("\(AppCalendar.shared.component(.day, from: day))")
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(inMonth ? Color.primary : Color.secondary.opacity(0.5))
        }
        .frame(height: 22)
        .opacity(inMonth ? 1.0 : 0.3)
        .help(helpText(day: day, status: status, inMonth: inMonth, nonSchool: nonSchool))
    }

    private func cellFill(status: AttendanceStatus, inMonth: Bool, nonSchool: Bool) -> Color {
        if !inMonth { return Color.gray.opacity(0.04) }
        if nonSchool { return Color.gray.opacity(0.08) }
        switch status {
        case .present: return .green.opacity(0.35)
        case .absent: return .red.opacity(0.55)
        case .tardy: return .blue.opacity(0.45)
        case .leftEarly: return .purple.opacity(0.45)
        case .unmarked: return Color.gray.opacity(0.10)
        }
    }

    private func helpText(day: Date, status: AttendanceStatus, inMonth: Bool, nonSchool: Bool) -> String {
        guard inMonth else { return "" }
        let label = DateFormatters.fullDate.string(from: day)
        if nonSchool { return "\(label) — non-school day" }
        if status == .unmarked { return "\(label) — no attendance recorded" }
        let reason = reasonByDay[AppCalendar.startOfDay(day)] ?? .none
        let reasonSuffix = reason == .none ? "" : " (\(reason.displayName))"
        return "\(label) — \(status.displayName)\(reasonSuffix)"
    }

    // MARK: Notes list

    private var notesList: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            ForEach(Array(notesEntries.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(DateFormatters.mediumDate.string(from: entry.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(statusLabel(status: entry.status, reason: entry.reason))
                            .font(.caption2)
                            .foregroundStyle(statusColor(entry.status))
                    }
                    .frame(width: 110, alignment: .leading)
                    Text(entry.text)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(AppTheme.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
            }
        }
    }

    private func statusLabel(status: AttendanceStatus, reason: AbsenceReason) -> String {
        if status == .absent && reason != .none {
            return "\(status.displayName) (\(reason.displayName))"
        }
        return status.displayName
    }

    private func statusColor(_ status: AttendanceStatus) -> Color {
        switch status {
        case .present: return .green
        case .absent: return .red
        case .tardy: return .blue
        case .leftEarly: return .purple
        case .unmarked: return .secondary
        }
    }

    // MARK: Data

    private func loadRecords() {
        let request = NSFetchRequest<CDAttendanceRecord>(entityName: "AttendanceRecord")
        request.predicate = NSPredicate(format: "studentID == %@", studentID.uuidString)
        do {
            records = try viewContext.fetch(request)
        } catch {
            Self.logger.warning("Load history failed: \(error.localizedDescription, privacy: .public)")
            records = []
        }
    }

}

// MARK: - Helper Types

private struct AttendanceHistoryNoteEntry: Identifiable {
    let id = UUID()
    let date: Date
    let status: AttendanceStatus
    let reason: AbsenceReason
    let text: String
}

private struct YearTotals {
    var present = 0
    var absent = 0
    var tardy = 0
    var leftEarly = 0
    var attendanceRate: Double? {
        let totalAttended = present + tardy + leftEarly
        let total = totalAttended + absent
        guard total > 0 else { return nil }
        return Double(totalAttended) / Double(total)
    }
}

// MARK: - Year Totals & Calendar Helpers

extension AttendanceStudentHistorySheet {
    private func computeYearTotals() -> YearTotals {
        var totals = YearTotals()
        // The current school year, not a trailing 365-day window: totals reset at the
        // configured year start instead of carrying last year's marks into the fall.
        let schoolYear = SchoolYear.containing(
            Date(),
            startMonth: FloridaGradeCalculator.schoolStartMonth,
            startDay: FloridaGradeCalculator.schoolStartDay,
            calendar: AppCalendar.shared
        )
        for record in records {
            guard let date = record.date, schoolYear.range.contains(date) else { continue }
            switch record.status {
            case .present: totals.present += 1
            case .absent: totals.absent += 1
            case .tardy: totals.tardy += 1
            case .leftEarly: totals.leftEarly += 1
            case .unmarked: break
            }
        }
        return totals
    }

    private func lastThreeMonths() -> [Date] {
        let cal = AppCalendar.shared
        let now = Date()
        guard let monthInterval = cal.dateInterval(of: .month, for: now) else { return [] }
        var months: [Date] = []
        for offset in stride(from: -2, through: 0, by: 1) {
            if let monthStart = cal.date(byAdding: .month, value: offset, to: monthInterval.start) {
                months.append(monthStart)
            }
        }
        return months
    }

    private func monthWeeks(for month: Date) -> [[Date]] {
        let cal = AppCalendar.shared
        guard let monthInterval = cal.dateInterval(of: .month, for: month) else { return [] }
        let firstOfMonth = monthInterval.start
        let firstWeekday = cal.firstWeekday
        let weekday = cal.component(.weekday, from: firstOfMonth)
        let leadingOffset = (weekday - firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -leadingOffset, to: firstOfMonth) else { return [] }
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

    private func percentString(_ rate: Double) -> String {
        let pct = Int((rate * 100).rounded())
        return "\(pct)%"
    }
}
