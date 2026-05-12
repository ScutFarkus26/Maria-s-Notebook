// ParshaTopicBrowserView.swift
// Searchable browser of all topics from parsha_metadata.json. Tap a topic
// to see the parshas that mention it; tap a parsha to jump to its next reading.

import SwiftUI
import CoreData

struct ParshaTopicBrowserView: View {
    @State private var search: String = ""

    private var entries: [ParshaTopicEntry] {
        ParshaMetadataService.allTopicsIndexed
    }

    private var filtered: [ParshaTopicEntry] {
        let query = search.trimmed().lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.topic.lowercased().contains(query) ||
            entry.parshaKeys.contains { HebrewParshaService.displayName(forKey: $0).lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filtered) { entry in
                        NavigationLink(value: entry.topic) {
                            TopicRow(entry: entry)
                        }
                    }
                } header: {
                    Text("\(filtered.count) topic\(filtered.count == 1 ? "" : "s")")
                }
            }
            .searchable(text: $search, prompt: "Search topics or parshas")
            .navigationTitle("Topics")
            .navigationDestination(for: String.self) { topic in
                if let entry = entries.first(where: { $0.topic == topic }) {
                    ParshaTopicDetailView(entry: entry)
                }
            }
            .navigationDestination(for: Date.self) { date in
                ThisWeeksParshaView(forShabbat: date)
            }
            .navigationDestination(for: CDLesson.self) { lesson in
                LessonDetailView(lesson: lesson, onSave: { _ in })
            }
        }
    }
}

private struct TopicRow: View {
    let entry: ParshaTopicEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(entry.topic)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                Text(entry.parshaKeys
                    .prefix(3)
                    .map { HebrewParshaService.displayName(forKey: $0) }
                    .joined(separator: " · ") +
                    (entry.parshaKeys.count > 3 ? " · +\(entry.parshaKeys.count - 3) more" : "")
                )
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(entry.parshaKeys.count)")
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.xxsmall)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }
}

private struct ParshaTopicDetailView: View {
    let entry: ParshaTopicEntry

    var body: some View {
        List {
            Section {
                ForEach(entry.parshaKeys, id: \.self) { key in
                    if let nextDate = HebrewParshaService.nextShabbat(forParshaKey: key) {
                        NavigationLink(value: nextDate) {
                            ParshaForTopicRow(parshaKey: key, nextShabbat: nextDate)
                        }
                    } else {
                        ParshaForTopicRow(parshaKey: key, nextShabbat: nil)
                    }
                }
            } header: {
                Text("Appears in \(entry.parshaKeys.count) parsha\(entry.parshaKeys.count == 1 ? "" : "s")")
            }
        }
        .navigationTitle(entry.topic)
        .inlineNavigationTitle()
    }
}

private struct ParshaForTopicRow: View {
    let parshaKey: String
    let nextShabbat: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
            Text(HebrewParshaService.displayName(forKey: parshaKey))
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.primary)
            if let nextShabbat {
                Text("Next reading: \(nextShabbat.formatted(date: .abbreviated, time: .omitted))")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            if let metadata = ParshaMetadataService.metadata(forKey: parshaKey) {
                Text(metadata.passageRange)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }
}
