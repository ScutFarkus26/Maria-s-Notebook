// ParshaLessonListView.swift
// Lists lessons tagged to a specific parsha. Provides "Add to Presentations…"
// and "New Lesson for <parsha>" actions.

import SwiftUI
import CoreData

struct ParshaLessonListView: View {
    let parshaKey: String
    let onSelectLesson: (CDLesson) -> Void

    @FetchRequest private var lessons: FetchedResults<CDLesson>

    @State private var showingNewLesson = false
    @State private var lessonToSchedule: CDLesson?

    init(parshaKey: String, onSelectLesson: @escaping (CDLesson) -> Void) {
        self.parshaKey = parshaKey
        self.onSelectLesson = onSelectLesson
        _lessons = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)],
            predicate: NSPredicate(format: "parshaKey == %@", parshaKey)
        )
    }

    var body: some View {
        Group {
            if lessons.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(lessons, id: \.id) { lesson in
                        ParshaLessonRow(lesson: lesson) {
                            onSelectLesson(lesson)
                        } onSchedule: {
                            lessonToSchedule = lesson
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(HebrewParshaService.displayName(forKey: parshaKey))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewLesson = true
                } label: {
                    Label("New Lesson", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewLesson) {
            ParshaLessonEditorSheet(parshaKey: parshaKey, existingLesson: nil)
        }
        .sheet(item: $lessonToSchedule) { lesson in
            ScheduleParshaLessonSheet(lesson: lesson) {
                lessonToSchedule = nil
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No lessons for \(HebrewParshaService.displayName(forKey: parshaKey))", systemImage: "book.closed")
        } description: {
            Text("Add your first lesson for this parsha.")
        } actions: {
            Button {
                showingNewLesson = true
            } label: {
                Label("New Lesson for \(HebrewParshaService.displayName(forKey: parshaKey))", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct ParshaLessonRow: View {
    @ObservedObject var lesson: CDLesson
    let onOpen: () -> Void
    let onSchedule: () -> Void

    private var subtitle: String {
        var parts: [String] = []
        let age = lesson.ageRange.trimmed()
        if !age.isEmpty {
            parts.append("Ages \(age)")
        }
        if let source = lesson.derivedFromLesson {
            parts.append("from \(source.name)")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onOpen()
            }

            Button {
                onSchedule()
            } label: {
                Label("Add to Presentations", systemImage: "calendar.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}
