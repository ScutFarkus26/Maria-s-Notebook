// LessonDetailWindowHost.swift
// Host view for displaying LessonDetailView in a separate macOS window.

import SwiftUI
import SwiftData

#if os(macOS)
struct LessonDetailWindowHost: View {
    let lessonID: UUID
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let fetchDescriptor = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
        if let lesson = modelContext.safeFetchFirst(fetchDescriptor) {
            LessonDetailView(lesson: lesson, onSave: { _ in
                // Save is handled by the view itself with SaveCoordinator
            })
            .frame(minWidth: 500, minHeight: 400)
        } else {
            ContentUnavailableView("Lesson Not Found", systemImage: "book.closed")
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
#endif
