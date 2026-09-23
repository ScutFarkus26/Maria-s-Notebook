// LiveLessonAssignments.swift
// The whole-assignment-table read the presentation editor needs, taken only
// where it is needed: live while a view that displays from it is on screen,
// once at the moment an action runs.

import SwiftUI
import CoreData

extension PresentationDetailContentView {
    /// Every assignment, read at the moment an action needs it (what the
    /// parent's live query held at that moment). Not for body code.
    var lessonAssignmentsAll: [CDLessonAssignment] {
        LessonAssignmentTable.fetchAll(in: viewContext)
    }
}

// MARK: - Live assignments, scoped to the views that display them

/// Hands its content the whole assignment table through a live
/// `@FetchRequest` — the same query `PresentationDetailView` used to hold for
/// its entire lifetime, now alive only while a view that displays from it
/// (Find Students, the post-presentation follow-up) is on screen.
struct LiveLessonAssignments<Content: View>: View {
    @FetchRequest(sortDescriptors: []) private var all: FetchedResults<CDLessonAssignment>
    let content: ([CDLessonAssignment]) -> Content

    init(@ViewBuilder content: @escaping ([CDLessonAssignment]) -> Content) {
        self.content = content
    }

    var body: some View {
        content(Array(all))
    }
}

/// The same unsorted whole-table read `LiveLessonAssignments` holds, once, for an action.
enum LessonAssignmentTable {
    static func fetchAll(in context: NSManagedObjectContext) -> [CDLessonAssignment] {
        context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
    }
}
