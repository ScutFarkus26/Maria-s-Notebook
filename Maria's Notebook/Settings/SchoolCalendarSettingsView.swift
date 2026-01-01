import SwiftUI
import SwiftData

struct SchoolCalendarSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @State private var currentMonth: Date = Date()
    @State private var selected: Set<DateComponents> = []
    @State private var nonSchoolDates: Set<Date> = []
    @State private var selectedSingleDate: Date = Date()

    private var monthInterval: DateInterval {
        let cal = calendar
        let start = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth)) ?? Date()
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                Text(monthTitle(currentMonth))
                    .font(.headline)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                Spacer()
                Label("Tap dates to mark as non-school", systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            CalendarMonthGridView(
                month: currentMonth,
                onDateToggled: { date, isNonSchool in
                    let day = calendar.startOfDay(for: date)
                    if isNonSchool {
                        nonSchoolDates.insert(day)
                    } else {
                        nonSchoolDates.remove(day)
                    }
                },
                nonSchoolDates: nonSchoolDates
            )

            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    clearMonth()
                } label: {
                    Label("Clear this month", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Button {
                    markWeekdaysAsSchoolDays()
                } label: {
                    Label("Keep weekends only", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)

            Text("These dates will be treated as non-school days across planning and attendance.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear { reload() }
    }

    private func reload() {
        let range = monthInterval.start ..< monthInterval.end
        nonSchoolDates = SchoolCalendar.nonSchoolDays(in: range, using: modelContext)
    }

    private func shiftMonth(_ delta: Int) {
        if let newDate = calendar.date(byAdding: .month, value: delta, to: currentMonth) {
            currentMonth = newDate
            reload()
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return df.string(from: date)
    }

    private func clearMonth() {
        let cal = calendar
        var d = cal.startOfDay(for: monthInterval.start)
        while d < monthInterval.end {
            let descriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == d })
            if let arr = try? modelContext.fetch(descriptor), let existing = arr.first {
                modelContext.delete(existing)
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        try? modelContext.save()
        reload()
    }

    private func markWeekdaysAsSchoolDays() {
        // Unmark weekends only for the current month: keep Sat/Sun marked; unmark weekdays
        let cal = calendar
        var d = cal.startOfDay(for: monthInterval.start)
        while d < monthInterval.end {
            let weekday = cal.component(.weekday, from: d)
            if weekday != 1 && weekday != 7 { // 1=Sun, 7=Sat
                // ensure weekdays are not marked as non-school
                let descriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == d })
                let items = (try? modelContext.fetch(descriptor)) ?? []
                if let existing = items.first {
                    modelContext.delete(existing)
                }
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        try? modelContext.save()
        reload()
    }
}
