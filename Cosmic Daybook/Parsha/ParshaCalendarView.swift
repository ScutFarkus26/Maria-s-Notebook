// ParshaCalendarView.swift
// The year list of the parsha screen: every Shabbat in the current Hebrew year and its parsha.
// Festival-displaced Shabbatot are labeled with the festival instead of a parsha key.

import SwiftUI
import CoreData

struct ParshaYearList: View {
    /// The Shabbat the screen shows; nil is this week.
    @Binding var selection: Date?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)],
        predicate: NSPredicate(format: "parshaKey != nil AND parshaKey != %@", "")
    )
    private var taggedLessons: FetchedResults<CDLesson>

    private var lessonCountsByParsha: [String: Int] {
        var counts: [String: Int] = [:]
        for lesson in taggedLessons {
            guard let key = lesson.parshaKey, !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return counts
    }

    private struct CalendarEntry: Identifiable {
        let date: Date
        let parshaKey: String?
        let festivalName: String?
        var id: Date { date }
    }

    /// The reading cycle to list: its Shabbatot, then Simchat Torah with V'Zot
    /// HaBerachah (`HebrewParshaService.parshaYearList`).
    private var entries: [CalendarEntry] {
        HebrewParshaService.parshaYearList().map {
            CalendarEntry(date: $0.date, parshaKey: $0.parshaKey, festivalName: $0.festivalName)
        }
    }

    private var entriesByMonth: [(monthLabel: String, items: [CalendarEntry])] {
        let calendar = HebrewParshaService.gregorian
        // Built once, not per body pass — `DateFormatter` construction is expensive
        // and this one never varies.
        let formatter = DateFormatters.monthYearGregorian

        let grouped = Dictionary(grouping: entries) { entry -> Date in
            let comps = calendar.dateComponents([.year, .month], from: entry.date)
            return calendar.date(from: comps) ?? entry.date
        }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (monthDate, items) in
                (monthLabel: formatter.string(from: monthDate), items: items.sorted { $0.date < $1.date })
            }
    }

    private var currentShabbat: Date {
        HebrewParshaService.shabbatOfWeek(containing: Date())
    }

    /// The year the listed readings belong to, taken from the list itself:
    /// naming it after today's Hebrew year titled October 2025's readings
    /// "5787" in the weeks after Rosh Hashana.
    private var yearTitle: String {
        guard let first = entries.first?.date,
              let year = HebrewParshaService.hebrew.dateComponents([.year], from: first).year
        else { return "Reading Cycle" }
        return "Reading Cycle \(year)"
    }

    /// This week's Shabbat, or the next one listed, so the calendar opens on
    /// the present rather than on last October.
    private var scrollTarget: Date? {
        let calendar = HebrewParshaService.gregorian
        let start = calendar.startOfDay(for: currentShabbat)
        return entries.first { calendar.startOfDay(for: $0.date) >= start }?.date
    }

    /// The highlighted row: the Shabbat picked, else this week's.
    private var highlighted: Binding<Date?> {
        Binding(get: { selection ?? scrollTarget }, set: { selection = $0 })
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: highlighted) {
                Section {
                    Text(yearTitle)
                        .font(AppTheme.ScaledFont.titleMedium)
                        .foregroundStyle(.primary)
                    Text("\(entries.filter { $0.parshaKey != HebrewParshaService.vzotHaberachahKey }.count) Shabbatot")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
                // Hoisted out of the row builder: all three were recomputed per row.
                // `Calendar(identifier:)` allocates an ICU calendar every time, and
                // `lessonCountsByParsha` walked the whole fetch to rebuild its
                // dictionary — so the counts alone were O(rows × tagged lessons).
                let calendar = HebrewParshaService.gregorian
                let today = currentShabbat
                let counts = lessonCountsByParsha
                ForEach(entriesByMonth, id: \.monthLabel) { group in
                    Section(group.monthLabel) {
                        ForEach(group.items) { entry in
                            CalendarRowView(
                                date: entry.date,
                                parshaKey: entry.parshaKey,
                                festivalName: entry.festivalName,
                                lessonCount: entry.parshaKey.map {
                                    HebrewParshaService.lessonCount(forParshaKey: $0, countsByTag: counts)
                                } ?? 0,
                                isCurrentWeek: calendar.isDate(entry.date, inSameDayAs: today)
                            )
                            .tag(entry.date)
                            .id(entry.date)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .task {
                // After the list's first layout; scrolling from the first
                // pass of `.task` landed before the rows existed.
                try? await Task.sleep(for: .milliseconds(150))
                if let scrollTarget {
                    proxy.scrollTo(scrollTarget, anchor: .top)
                }
            }
        }
    }
}

private struct CalendarRowView: View {
    let date: Date
    let parshaKey: String?
    let festivalName: String?
    let lessonCount: Int
    let isCurrentWeek: Bool

    private var title: String {
        if parshaKey == HebrewParshaService.vzotHaberachahKey {
            return "\(HebrewParshaService.displayName(forKey: HebrewParshaService.vzotHaberachahKey)) (Simchat Torah)"
        }
        if let key = parshaKey { return HebrewParshaService.displayName(forKey: key) }
        if let festivalName { return festivalName }
        return "—"
    }

    private var isFestival: Bool { parshaKey == nil && festivalName != nil }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            VStack(alignment: .leading, spacing: 0) {
                Text(date.formatted(.dateTime.day()))
                    .font(AppTheme.ScaledFont.titleSmall)
                    .foregroundStyle(.primary)
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                HStack(spacing: AppTheme.Spacing.small) {
                    Text(title)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(isFestival ? Color.accentColor : .primary)
                    if isCurrentWeek {
                        Text("This week")
                            .font(AppTheme.ScaledFont.captionSmallSemibold)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if let key = parshaKey, let metadata = ParshaMetadataService.metadata(forKey: key) {
                    Text("\(metadata.torahReference) (\(metadata.passageRange))")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if lessonCount > 0 {
                Text("\(lessonCount)")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.small)
                    .padding(.vertical, AppTheme.Spacing.xxsmall)
                    .capsuleFill(Color.secondary.opacity(0.15))
            }
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }
}
