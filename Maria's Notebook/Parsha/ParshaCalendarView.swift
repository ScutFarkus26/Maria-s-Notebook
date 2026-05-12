// ParshaCalendarView.swift
// Annual calendar of every Shabbat in the current Hebrew year and its parsha.
// Festival-displaced Shabbatot are labeled with the festival instead of a parsha key.

import SwiftUI
import CoreData

struct ParshaCalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext

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

    private var entries: [CalendarEntry] {
        HebrewParshaService.shabbatotForHebrewYear(containing: Date()).map {
            CalendarEntry(date: $0.date, parshaKey: $0.parshaKey, festivalName: $0.festivalName)
        }
    }

    private var entriesByMonth: [(monthLabel: String, items: [CalendarEntry])] {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.calendar = calendar

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

    private var yearTitle: String {
        let hebrew = Calendar(identifier: .hebrew)
        let year = hebrew.dateComponents([.year], from: currentShabbat).year ?? 0
        return "Hebrew Year \(year)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(yearTitle)
                        .font(AppTheme.ScaledFont.titleMedium)
                        .foregroundStyle(.primary)
                    Text("\(entries.count) Shabbatot")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(entriesByMonth, id: \.monthLabel) { group in
                    Section(group.monthLabel) {
                        ForEach(group.items) { entry in
                            NavigationLink(value: entry.date) {
                                CalendarRowView(
                                    date: entry.date,
                                    parshaKey: entry.parshaKey,
                                    festivalName: entry.festivalName,
                                    lessonCount: entry.parshaKey.flatMap { lessonCountsByParsha[$0] } ?? 0,
                                    isCurrentWeek: Calendar(identifier: .gregorian).isDate(entry.date, inSameDayAs: currentShabbat)
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Parsha Calendar")
            .navigationDestination(for: Date.self) { date in
                ThisWeeksParshaView(forShabbat: date)
            }
            .navigationDestination(for: CDLesson.self) { lesson in
                LessonDetailView(lesson: lesson, onSave: { _ in })
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
                    Text(metadata.passageRange)
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
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }
}
