// LessonDetailWindowHost.swift
// Host view for displaying LessonDetailView in a separate macOS window.

import SwiftUI
import CoreData

#if os(macOS)
struct LessonDetailWindowHost: View {
    let lessonID: UUID
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        if let lesson = viewContext.object(CDLesson.self, id: lessonID) {
            LessonDetailView(lesson: lesson, onSave: { _ in
                // Save is handled by the view itself with SaveCoordinator
            })
            .frame(minWidth: 500, minHeight: 400)
            .navigationTitle(lesson.name.isEmpty ? "Lesson" : lesson.name)
        } else {
            ContentUnavailableView("Lesson Not Found", systemImage: "book.closed")
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
#endif
