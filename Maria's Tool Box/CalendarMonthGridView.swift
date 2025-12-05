import SwiftUI
import SwiftData

struct CalendarMonthGridView: View {
    @Environment(\.modelContext) private var modelContext
    var month: Date
    var calendar: Calendar = .current
    var onDateToggled: ((Date, Bool) -> Void)? = nil
    var nonSchoolDates: Set<Date>? = nil

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
        let df = DateFormatter()
        // Unwrap with robust fallbacks to ensure a non-optional array
        let base: [String] = df.shortStandaloneWeekdaySymbols
            ?? df.shortWeekdaySymbols
            ?? df.weekdaySymbols
            ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        // Convert calendar.firstWeekday (1...7) to zero-based index
        let start = max(1, min(7, calendar.firstWeekday)) - 1

        // If start is zero or out of bounds, just return base
        guard start > 0, start < base.count else { return base }

        // Rotate symbols so that they start at the calendar's firstWeekday
        let head = Array(base[start...])
        let tail = Array(base[..<start])
        return head + tail
    }

    var body: some View {
        VStack(spacing: 8) {
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            // Weeks grid
            VStack(spacing: 8) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { date in
                            DayCell(date: date, calendar: calendar, nonSchoolDates: nonSchoolDates) { d in
                                let newState = (try? SchoolCalendar.toggleNonSchoolDay(d, using: modelContext)) ?? SchoolCalendar.isNonSchoolDay(d, using: modelContext)
                                onDateToggled?(d, newState)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    @Environment(\.modelContext) private var modelContext
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
                        return SchoolCalendar.isNonSchoolDay(d, using: modelContext)
                    }
                }()
                Button(action: { onTap(d) }) {
                    Text(label)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isNS ? Color.red : Color.primary)
                        .frame(height: 40)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isNS ? Color.red.opacity(0.15) : (isToday(d) ? Color.primary.opacity(0.06) : Color.clear))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(label), \(isNS ? "No School" : "School Day")"))
            } else {
                Color.clear.frame(height: 40)
            }
        }
    }
}

