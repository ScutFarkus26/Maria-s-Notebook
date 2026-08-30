// ChecklistLessonNavigator.swift
// One jump: from anything that names a lesson to that lesson's row in the
// checklist grid.
//
// The grid draws a single curriculum area at a time, so it has to be told which
// one to switch to. Resolving that here keeps every caller down to the lesson id
// it already has — presentation cards carry a `lessonID`, not the lesson.

import CoreData
import SwiftUI

enum ChecklistLessonNavigator {

    /// Opens the Checklist on the lesson's own area and flashes its row.
    ///
    /// Does nothing when the lesson is gone: a presentation card can outlive the
    /// lesson it was made from, and sending the guide to an unrelated area would
    /// be worse than the menu item doing nothing.
    @MainActor
    static func reveal(lessonID: UUID, in context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
        request.fetchLimit = 1
        guard let lesson = context.safeFetch(request).first else { return }
        AppRouter.shared.navigateToChecklist(lessonID: lessonID, area: lesson.area)
    }
}

/// "Show in Checklist" as a context-menu item.
///
/// The context is handed in rather than read from `@Environment`: menu content
/// is built outside the presenting view's own tree, so anything it expects to
/// find in the environment has to be captured by the view that owns the menu.
struct ShowInChecklistButton: View {
    let lessonID: UUID
    let context: NSManagedObjectContext

    var body: some View {
        Button("Show in Checklist", systemImage: "list.clipboard") {
            ChecklistLessonNavigator.reveal(lessonID: lessonID, in: context)
        }
    }
}
