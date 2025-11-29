import SwiftUI

struct PlanningWeekView: View {
    @Environment(\.calendar) private var calendar
    @State private var weekStart: Date = Self.monday(for: Date())

    private var days: [Date] {
        (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        WeekGrid(days: days)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack(spacing: 10) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to Schedule")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Next lessons that still need a time slot.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Empty state placeholder (replace with your list later)
            VStack(spacing: 12) {
                Spacer(minLength: 20)
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("Nothing left to plan")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("All next lessons are on the calendar.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 280)
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    weekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Text(weekRangeString)
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Today") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    weekStart = Self.monday(for: Date(), calendar: calendar)
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers
    private var weekRangeString: String {
        guard let end = calendar.date(byAdding: .day, value: 4, to: weekStart) else { return "" }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(fmt.string(from: weekStart)) - \(fmt.string(from: end))"
    }

    static func monday(for date: Date, calendar: Calendar = .current) -> Date {
        let cal = calendar
        let startOfDay = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: startOfDay) // 1=Sun, 2=Mon, ...
        let daysToSubtract = (weekday + 5) % 7 // Mon->0, Tue->1, ... Sun->6
        return cal.date(byAdding: .day, value: -daysToSubtract, to: startOfDay) ?? startOfDay
    }
}

// MARK: - Week Grid
private struct WeekGrid: View {
    @Environment(\.calendar) private var calendar
    let days: [Date]

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 160), spacing: 24), count: 5)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(days, id: \.self) { day in
                DayColumn(day: day)
            }
        }
    }
}

// MARK: - Day Column
private struct DayColumn: View {
    @Environment(\.calendar) private var calendar
    let day: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Day header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(dayNumber)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .padding(.bottom, 2)

            // Morning
            Text("Morning")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            DropZone()
                .frame(minHeight: 220)

            // Afternoon
            Text("Afternoon")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            DropZone()
                .frame(minHeight: 220)
        }
    }

    private var dayName: String {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEE")
        return fmt.string(from: day)
    }

    private var dayNumber: String {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("d")
        return fmt.string(from: day)
    }
}

// MARK: - Drop Zone
private struct DropZone: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .foregroundStyle(Color.primary.opacity(0.25))
            Text("Drop lesson here")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    PlanningWeekView()
        .frame(minWidth: 1000, minHeight: 600)
}
