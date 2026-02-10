import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
            
            Divider()
                .padding(.vertical, 8)
            
            // Florida Grade Guidelines
            #if os(macOS)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "graduationcap.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Florida Grade Guidelines")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                LazyVGrid(columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ], spacing: 4) {
                    GradeGuidelineRowCompact(age: "Under 6", grade: "Kindergarten")
                    GradeGuidelineRowCompact(age: "Age 6", grade: "1st Grade")
                    GradeGuidelineRowCompact(age: "Age 7", grade: "2nd Grade")
                    GradeGuidelineRowCompact(age: "Age 8", grade: "3rd Grade")
                    GradeGuidelineRowCompact(age: "Age 9", grade: "4th Grade")
                    GradeGuidelineRowCompact(age: "Age 10", grade: "5th Grade")
                    GradeGuidelineRowCompact(age: "Age 11", grade: "6th Grade")
                    GradeGuidelineRowCompact(age: "Age 12+", grade: "Graduated")
                }
                .padding(.top, 4)
            }
            .padding(.top, 4)
            #else
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "graduationcap.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                    Text("Florida Grade Guidelines")
                        .font(.headline)
                }
                
                Text("Grade assignments based on student age as of September 1st")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 10) {
                    GradeGuidelineRow(age: "Under 6", grade: "Kindergarten")
                    GradeGuidelineRow(age: "Age 6", grade: "1st Grade")
                    GradeGuidelineRow(age: "Age 7", grade: "2nd Grade")
                    GradeGuidelineRow(age: "Age 8", grade: "3rd Grade")
                    GradeGuidelineRow(age: "Age 9", grade: "4th Grade")
                    GradeGuidelineRow(age: "Age 10", grade: "5th Grade")
                    GradeGuidelineRow(age: "Age 11", grade: "6th Grade")
                    GradeGuidelineRow(age: "Age 12+", grade: "Graduated")
                }
            }
            .padding(.top, 8)
            #endif
        }
        .task {
            await reload()
        }
    }

    private func reload() async {
        let range = monthInterval.start ..< monthInterval.end
        nonSchoolDates = await SchoolCalendar.nonSchoolDays(in: range, using: modelContext)
    }

    private func shiftMonth(_ delta: Int) {
        if let newDate = calendar.date(byAdding: .month, value: delta, to: currentMonth) {
            currentMonth = newDate
            Task {
                await reload()
            }
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
            var descriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == d })
            descriptor.fetchLimit = 1
            if let arr = try? modelContext.fetch(descriptor), let existing = arr.first {
                modelContext.delete(existing)
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        try? modelContext.save()
        Task {
            await reload()
        }
    }

    private func markWeekdaysAsSchoolDays() {
        // Unmark weekends only for the current month: keep Sat/Sun marked; unmark weekdays
        let cal = calendar
        var d = cal.startOfDay(for: monthInterval.start)
        while d < monthInterval.end {
            let weekday = cal.component(.weekday, from: d)
            if weekday != 1 && weekday != 7 { // 1=Sun, 7=Sat
                // ensure weekdays are not marked as non-school
                var descriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == d })
                descriptor.fetchLimit = 1
                let items = (try? modelContext.fetch(descriptor)) ?? []
                if let existing = items.first {
                    modelContext.delete(existing)
                }
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        try? modelContext.save()
        Task {
            await reload()
        }
    }
}

private struct GradeGuidelineRow: View {
    let age: String
    let grade: String
    
    private var backgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text(age)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .leading)
            
            Text(grade)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
    }
}

#if os(macOS)
private struct GradeGuidelineRowCompact: View {
    let age: String
    let grade: String
    
    var body: some View {
        HStack(spacing: 6) {
            Text(age)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("→")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(grade)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
