import CoreData
import Foundation

extension LessonCatalog {
    /// The lesson with `id` as `context` sees it — for a view that used to
    /// fetch it by id (`object(_:id:)`, a scan of the lesson table) on every
    /// body pass.
    ///
    /// The catalog's row when it belongs to `context` and is not deleted: the
    /// same managed object the fetch returned, found by a dictionary lookup,
    /// and read through the catalog so the view is invalidated when the lesson
    /// table changes. Otherwise the fetch the view made before, so a view handed
    /// another context, or a lesson inserted this run-loop turn that the
    /// catalog's controller has not reported yet, reads exactly what it did.
    func lesson(id: UUID, in context: NSManagedObjectContext) -> CDLesson? {
        if let lesson = lesson(id: id), lesson.managedObjectContext === context, !lesson.isDeleted {
            return lesson
        }
        return context.object(CDLesson.self, id: id)
    }
}
