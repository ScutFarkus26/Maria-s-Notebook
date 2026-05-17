// ParshaBrowseView.swift
// Column-2 view when the "Parshas" sentinel is selected in the areas column.
// Shows the 54 parshas in annual-cycle order; tapping one pushes to the lessons list.

import SwiftUI
import CoreData

struct ParshaBrowseView: View {
    let onSelectLesson: (CDLesson) -> Void

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)])
    private var allLessons: FetchedResults<CDLesson>

    @State private var selectedParshaKey: String?

    private var lessonCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for lesson in allLessons {
            if let key = lesson.parshaKey, !key.isEmpty {
                counts[key, default: 0] += 1
            }
        }
        return counts
    }

    private var currentWeekParshaKey: String? {
        HebrewParshaService.currentParshaKey()
    }

    var body: some View {
        NavigationStack {
            List(selection: $selectedParshaKey) {
                Section {
                    ForEach(HebrewParshaService.allParshaKeys, id: \.self) { key in
                        NavigationLink(value: key) {
                            ParshaBrowseRow(
                                parshaKey: key,
                                lessonCount: lessonCounts[key] ?? 0,
                                isCurrentWeek: key == currentWeekParshaKey
                            )
                        }
                    }
                } header: {
                    if let currentKey = currentWeekParshaKey {
                        Text("This week: \(HebrewParshaService.displayName(forKey: currentKey))")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Parshas")
            .navigationDestination(for: String.self) { key in
                ParshaLessonListView(parshaKey: key, onSelectLesson: onSelectLesson)
            }
        }
    }
}

struct ParshaBrowseRow: View {
    let parshaKey: String
    let lessonCount: Int
    let isCurrentWeek: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isCurrentWeek ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(HebrewParshaService.displayName(forKey: parshaKey))
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.primary)

            Spacer()

            if lessonCount > 0 {
                Text("\(lessonCount)")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }

            if isCurrentWeek {
                Text("this week")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
