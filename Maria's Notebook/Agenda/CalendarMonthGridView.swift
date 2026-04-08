import SwiftUI
import CoreData
import OSLog

struct CalendarMonthGridView: View {
    private static let logger = Logger.planning
    @Environment(\.managedObjectContext) private var viewContext
    var month: Date
    var calendar: Calendar = .current
    var onDateToggled: ((Date, Bool) -> Void)?
    var nonSchoolDates: Set<Date>?
    @State private var computedNonSchoolDates: Set<Date>?

    private var startOfMonth: Date {
        let comps = calendar.dateComponents([.year, .month], from: month)
        return calendar.date(from: comps) ?? month
    }

    private var daysInMonth: Int {
        (calendar.range(of: .day, in: .month, for: startOfMonth)?.count) ?? 30
    }

    private var leadingEmptyDays: Int {
        let firstWeekdayOfMonth = calendar.component(.weekday, from: startOfMonth)
        return (firstWeekdayOfMonth - calendar.firstWeekday + 7) % 7
    }

    private var weeks: [[Date?]] {
        var cells: [Date?] = Array(repeating: nil, count: leadingEmptyDays)
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0+7]) }
    }

    private var weekdaySymbols: [String] {
        // Prefer standalone symbols; fall back as needed
        let base = DateFormatters.weekdayAbbrev.shortStandaloneWeekdaySymbols
            ?? DateFormatters.weekdayAbbrev.shortWeekdaySymbols
            ?? DateFormatters.weekdayAbbrev.weekdaySymbols
            ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        let start = max(1, min(7, calendar.firstWeekday)) - 1
        guard start > 0, start < base.count else { return base }

        let head = Array(base[start...])
        let tail = Array(base[..<start])
        return head + tail
    }

    private func loadNonSchoolDates() async {
        // Only compute if not provided by parent
        guard nonSchoolDates == nil else { return }
        let start = startOfMonth
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let set = await SchoolCalendar.nonSchoolDays(in: start..<end, using: viewContext)
        await MainActor.run { computedNonSchoolDates = set }
    }

    var body: some View {
        VStack(spacing: 8) {
            weekdayHeaders
            weeksGrid
        }
        .task {
            if nonSchoolDates == nil {
                await loadNonSchoolDates()
            }
        }
        .onChange(of: month) { _, _ in
            Task { if nonSchoolDates == nil { await loadNonSchoolDates() } }
        }
        .onChange(of: calendar) { _, _ in
            Task { if nonSchoolDates == nil { await loadNonSchoolDates() } }
        }
    }

    private var weekdayHeaders: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    private var weeksGrid: some View {
        VStack(spacing: 8) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, date in
                        DayCell(
                            date: date,
                            calendar: calendar,
                            nonSchoolDates: nonSchoolDates ?? computedNonSchoolDates,
                            onTap: { d in handleDayTap(d) }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func handleDayTap(_ d: Date) {
        Task {
            let toggleResult: Bool?
            do {
                toggleResult = try await SchoolCalendar.toggleNonSchoolDay(d, using: viewContext)
            } catch {
                Self.logger.warning("Failed to toggle non-school day: \(error)")
                toggleResult = nil
            }
            do {
                try viewContext.save()
            } catch {
                Self.logger.warning("Failed to save after toggle: \(error)")
            }
            let newState: Bool
            if let result = toggleResult {
                newState = result
            } else {
                newState = await SchoolCalendar.isNonSchoolDay(d, using: viewContext)
            }
            await MainActor.run {
                onDateToggled?(d, newState)
            }
            if nonSchoolDates == nil {
                let start: Date = startOfMonth
                let end: Date = calendar.date(byAdding: .month, value: 1, to: start) ?? start
                let set: Set<Date> = await SchoolCalendar.nonSchoolDays(in: start..<end, using: viewContext)
                await MainActor.run { computedNonSchoolDates = set }
            }
        }
    }
}

private struct DayCell: View {
    @Environment(\.managedObjectContext) private var viewContext
    let date: Date?
    let calendar: Calendar
    let nonSchoolDates: Set<Date>?
    let onTap: (Date) -> Void

    private var label: String {
        guard let date else { return "" }
        return String(calendar.component(.day, from: date))
    }

    private func isToday(_ d: Date) -> Bool {
        calendar.isDateInToday(d)
    }

    var body: some View {
        Group {
            if let d = date {
                let isNS: Bool = {
                    if let set = nonSchoolDates {
                        return set.contains(calendar.startOfDay(for: d))
                    } else {
                        return false
                    }
                }()
                Button(action: { onTap(d) }, label: {
                    Text(label)
                        .font(AppTheme.ScaledFont.titleSmall)
                        .foregroundStyle(isNS ? Color.red : Color.primary)
                        .frame(height: 40)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    isNS
                                        ? Color.red.opacity(UIConstants.OpacityConstants.accent)
                                        : (isToday(d) ? Color.primary.opacity(UIConstants.OpacityConstants.veryFaint) : Color.clear)
                                )
                        )
                })
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(label), \(isNS ? "No School" : "School Day")"))
            } else {
                Color.clear.frame(height: 40)
            }
        }
    }
}
