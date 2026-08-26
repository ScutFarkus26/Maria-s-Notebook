// LinkedNotebookLessonsPanel.swift
// The album side of the lesson ↔ album link. While reading a lesson in an
// album, shows the guide's own notebook lessons that point at this stretch
// of pages — their write-up, materials, and teacher notes for the same
// lesson — and jumps to them.
//
// Sits next to RelatedLessonsPanel, which does the same job for other
// ALBUM lessons. This one crosses into the notebook.

import CoreData
import SwiftUI

struct LinkedNotebookLessonsPanel: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.appRouter) private var appRouter
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    let album: Album
    let currentPage: Int
    let onOpened: () -> Void

    @State private var showMatchSheet = false

    /// Lessons linked anywhere in the page range of the lesson being read.
    private var linked: [CDLesson] {
        let range = album.lessonRange(forPage: currentPage)
        return CDLesson.lessonsInAlbum(album.id, context: context)
            .filter { range.contains(Int($0.albumPageIndex)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notebook Lesson", systemImage: "book.closed")
                .font(.headline)
            let lessons = linked
            if lessons.isEmpty {
                Text("No lesson in your notebook is linked to this page yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Find a Matching Lesson…") { showMatchSheet = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                ForEach(lessons) { lesson in
                    row(lesson)
                }
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .sheet(isPresented: $showMatchSheet) {
            LessonAlbumMatchSheet(lessons: unlinkedCandidates())
        }
    }

    private func row(_ lesson: CDLesson) -> some View {
        Button {
            open(lesson)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(album.subject.color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(LessonFormatter.titleOrFallback(lesson.name))
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.leading)
                    let detail = [lesson.area, lesson.sequence]
                        .map { $0.trimmed() }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ lesson: CDLesson) {
        guard let id = lesson.id else { return }
        onOpened()
        #if os(macOS)
        // Keep the album open alongside the lesson rather than navigating
        // the reader away from the page the guide is on.
        openLessonInNewWindow(id)
        #else
        appRouter.navigateToLesson(id)
        #endif
    }

    /// Lessons worth offering when nothing is linked here — everything
    /// unlinked, since the matcher does the narrowing itself.
    private func unlinkedCandidates() -> [CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "albumID == nil OR albumID == %@", "")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]
        return context.safeFetch(request)
    }
}
