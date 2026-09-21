// LessonDetailWindowHost.swift
// Host view for displaying LessonDetailView in a separate macOS window.

import CoreData
import SwiftUI

#if os(macOS)
struct LessonDetailWindowHost: View {
    let lessonID: UUID

    var body: some View {
        EntityWindowHost(
            id: lessonID,
            minSize: CGSize(width: 500, height: 400),
            notFound: WindowHostNotFound(
                "Lesson Not Found",
                systemImage: "book.closed",
                minSize: CGSize(width: 400, height: 300)
            )
        ) { (lesson: CDLesson) in
            LessonDetailView(lesson: lesson, onSave: { _ in
                // Save is handled by the view itself with SaveCoordinator
            })
            .navigationTitle(lesson.name.isEmpty ? "Lesson" : lesson.name)
        }
    }
}
#endif
