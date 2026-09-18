// TagLessonToParshaSheet.swift
// Searchable picker that retroactively tags an existing CDLesson to a parsha key.

import SwiftUI
import CoreData

struct TagLessonToParshaSheet: View {
    let parshaKey: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)])
    private var allLessons: FetchedResults<CDLesson>

    @State private var search: String = ""
    @State private var untaggedOnly: Bool = true

    private var parshaName: String {
        HebrewParshaService.displayName(forKey: parshaKey)
    }

    private var filtered: [CDLesson] {
        let query = search.trimmed().lowercased()
        let base: [CDLesson] = untaggedOnly
            ? allLessons.filter { ($0.parshaKey ?? "").isEmpty }
            : Array(allLessons)
        guard !query.isEmpty else { return base }
        return base.filter { lesson in
            lesson.name.lowercased().contains(query) ||
            lesson.area.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Untagged lessons only", isOn: $untaggedOnly)
                }
                Section {
                    if filtered.isEmpty {
                        Text(emptyMessage)
                            .font(AppTheme.ScaledFont.body)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered, id: \.id) { lesson in
                            Button {
                                tag(lesson)
                            } label: {
                                lessonRow(lesson)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("\(filtered.count) lesson\(filtered.count == 1 ? "" : "s")")
                }
            }
            .searchable(text: $search, prompt: "Search lessons")
            .navigationTitle("Tag to \(parshaName)")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDone()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 540)
        #endif
    }

    private var emptyMessage: String {
        if untaggedOnly {
            return "No untagged lessons. Toggle off to pick from all lessons."
        }
        return "No lessons match your search."
    }

    private func lessonRow(_ lesson: CDLesson) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                if !lesson.area.isEmpty {
                    Text(lesson.area)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let existing = lesson.parshaKey, !existing.isEmpty, existing != parshaKey {
                Text(HebrewParshaService.displayName(forKey: existing))
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.small)
                    .padding(.vertical, AppTheme.Spacing.xxsmall)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }

    private func tag(_ lesson: CDLesson) {
        lesson.parshaKey = parshaKey
        let repo = LessonRepository(context: viewContext, saveCoordinator: saveCoordinator)
        _ = repo.save(reason: "Tag lesson to parsha")
        onDone()
        dismiss()
    }
}
