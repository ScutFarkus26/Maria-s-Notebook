import SwiftUI
import SwiftData

/// A year-at-a-glance perpetual calendar showing all 12 months with day numbers,
/// US federal holidays, non-school days, and today highlighted.
struct PerpetualCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var displayYear: Int = Calendar.current.component(.year, from: Date())
    @State private var nonSchoolDates: Set<Date> = []

    private var calendar: Calendar { AppCalendar.shared }

    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Calendar") {
                yearStepper
            }

            Divider()

            ScrollView {
                yearGrid
                    .padding(20)
            }
        }
        .task(id: displayYear) {
            await loadNonSchoolDays()
        }
    }

    // MARK: - Year Stepper

    private var yearStepper: some View {
        HStack(spacing: 12) {
            Button {
                displayYear -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(String(displayYear))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 60)

            Button {
                displayYear += 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Today") {
                displayYear = calendar.component(.year, from: Date())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Year Grid

    private var yearGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 20)
        ]
        return LazyVGrid(columns: columns, spacing: 20) {
            ForEach(1...12, id: \.self) { month in
                MonthCard(
                    year: displayYear,
                    month: month,
                    calendar: calendar,
                    nonSchoolDates: nonSchoolDates
                )
            }
        }
    }

    // MARK: - Data Loading

    private func loadNonSchoolDays() async {
        var comps = DateComponents()
        comps.year = displayYear
        comps.month = 1
        comps.day = 1
        guard let start = calendar.date(from: comps) else { return }
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else { return }
        let set = await SchoolCalendar.nonSchoolDays(in: start..<end, using: modelContext)
        await MainActor.run { nonSchoolDates = set }
    }
}

// MARK: - Month Card

private struct MonthCard: View {
    let year: Int
    let month: Int
    let calendar: Calendar
    let nonSchoolDates: Set<Date>

    private var monthName: String {
        calendar.monthSymbols[month - 1]
    }

    private var daysInMonth: Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }

    private var firstWeekday: Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = calendar.date(from: comps) else { return 1 }
        return (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
    }

    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Month header
            Text(monthName)
                .font(.headline)
                .padding(.bottom, 2)

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            let cells = buildCells()
            let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
                        DayCellView(cell: cell)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    private func buildCells() -> [DayCell] {
        var cells: [DayCell] = Array(repeating: DayCell(day: 0, isToday: false, isNonSchool: false, holiday: nil),
                                     count: firstWeekday)
        let today = Date()
        for day in 1...daysInMonth {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            let date = calendar.date(from: comps)
            let startOfDay = date.map { calendar.startOfDay(for: $0) }
            let isToday = date.map { calendar.isDateInToday($0) } ?? false
            let isNonSchool = startOfDay.map { nonSchoolDates.contains($0) } ?? false
            let holiday = PerpetualHolidays.holiday(month: month, day: day, year: year)
            cells.append(DayCell(day: day, isToday: isToday, isNonSchool: isNonSchool, holiday: holiday))
        }
        // Pad to complete the last week
        while cells.count % 7 != 0 {
            cells.append(DayCell(day: 0, isToday: false, isNonSchool: false, holiday: nil))
        }
        return cells
    }
}

// MARK: - Day Cell

private struct DayCell {
    let day: Int
    let isToday: Bool
    let isNonSchool: Bool
    let holiday: String?

    var isEmpty: Bool { day == 0 }
}

private struct DayCellView: View {
    let cell: DayCell

    var body: some View {
        if cell.isEmpty {
            Color.clear
                .frame(height: 24)
        } else {
            Text("\(cell.day)")
                .font(.caption.monospacedDigit())
                .fontWeight(cell.isToday ? .bold : .regular)
                .foregroundStyle(foregroundColor)
                .frame(height: 24)
                .frame(maxWidth: .infinity)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .help(helpText)
        }
    }

    private var foregroundColor: Color {
        if cell.isToday {
            return .white
        }
        if cell.isNonSchool {
            return .red
        }
        if cell.holiday != nil {
            return .blue
        }
        return .primary
    }

    private var background: some ShapeStyle {
        if cell.isToday {
            return AnyShapeStyle(Color.accentColor)
        }
        if cell.isNonSchool {
            return AnyShapeStyle(Color.red.opacity(0.12))
        }
        if cell.holiday != nil {
            return AnyShapeStyle(Color.blue.opacity(0.1))
        }
        return AnyShapeStyle(Color.clear)
    }

    private var helpText: String {
        var parts: [String] = []
        if let holiday = cell.holiday {
            parts.append(holiday)
        }
        if cell.isNonSchool {
            parts.append("Non-school day")
        }
        if cell.isToday {
            parts.append("Today")
        }
        return parts.isEmpty ? "\(cell.day)" : parts.joined(separator: " \u{2022} ")
    }
}

// MARK: - US Federal Holidays

enum PerpetualHolidays {
    /// Returns the holiday name for a given date, or nil if not a holiday.
    /// Covers fixed-date and floating US federal holidays.
    static func holiday(month: Int, day: Int, year: Int) -> String? {
        // Fixed-date holidays
        switch (month, day) {
        case (1, 1): return "New Year's Day"
        case (6, 19): return "Juneteenth"
        case (7, 4): return "Independence Day"
        case (11, 11): return "Veterans Day"
        case (12, 25): return "Christmas Day"
        default: break
        }

        // Floating holidays (nth weekday of month)
        let cal = AppCalendar.shared
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = cal.date(from: comps) else { return nil }
        let weekday = cal.component(.weekday, from: date)
        let weekOfMonth = (day - 1) / 7 + 1

        switch (month, weekday, weekOfMonth) {
        // MLK Day: 3rd Monday of January
        case (1, 2, 3): return "MLK Day"
        // Presidents' Day: 3rd Monday of February
        case (2, 2, 3): return "Presidents' Day"
        // Memorial Day: last Monday of May
        case (5, 2, _) where isLastWeekdayOccurrence(day: day, month: month, year: year, weekday: 2):
            return "Memorial Day"
        // Labor Day: 1st Monday of September
        case (9, 2, 1): return "Labor Day"
        // Columbus Day: 2nd Monday of October
        case (10, 2, 2): return "Columbus Day"
        // Thanksgiving: 4th Thursday of November
        case (11, 5, 4): return "Thanksgiving"
        default: return nil
        }
    }

    private static func isLastWeekdayOccurrence(day: Int, month: Int, year: Int, weekday: Int) -> Bool {
        let cal = AppCalendar.shared
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = cal.date(from: comps) else { return false }
        let nextWeek = cal.date(byAdding: .day, value: 7, to: date)
        guard let nextWeek else { return false }
        return cal.component(.month, from: nextWeek) != month
    }
}

#Preview {
    PerpetualCalendarView()
        .previewEnvironment()
}
