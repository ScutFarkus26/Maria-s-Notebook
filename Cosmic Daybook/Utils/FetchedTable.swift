import CoreData
import OSLog

nonisolated private let logger = Logger.database

/// One `NSFetchedResultsController` over a whole table on the view context.
///
/// `RosterStore` and `LessonCatalog` each own one so that a table is fetched
/// once per classroom workspace, not once per view on screen. The controller
/// re-evaluates on every `NSManagedObjectContextObjectsDidChange` the context
/// posts — a local edit once the run loop turns, a save, or a CloudKit import
/// merged in by `automaticallyMergesChangesFromParent` — and `onChange` runs
/// after each one so the owner rebuilds its cached arrays exactly once per
/// change instead of once per view body. That is the same notification an
/// `@FetchRequest` listens to, so reactivity is unchanged; only the fan-out is.
@MainActor
final class FetchedTable<Object: NSManagedObject>: NSObject, NSFetchedResultsControllerDelegate {
    private let controller: NSFetchedResultsController<Object>

    /// Called on the main actor after every change the controller sees.
    var onChange: (@MainActor () -> Void)?

    /// The rows in the order the sort descriptors gave them.
    var objects: [Object] { controller.fetchedObjects ?? [] }

    init(_ type: Object.Type = Object.self, context: NSManagedObjectContext, sortDescriptors: [NSSortDescriptor]) {
        let request = CDFetchRequest(type)
        request.sortDescriptors = sortDescriptors
        controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        super.init()
        controller.delegate = self
        do {
            try controller.performFetch()
        } catch {
            logger.error(
                "FetchedTable<\(String(describing: type))> initial fetch failed: \(error.localizedDescription)"
            )
        }
    }

    nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
        // The controller calls its delegate on its context's queue, and both
        // owners sit on the main-queue view context, so this is the main actor.
        MainActor.assumeIsolated { onChange?() }
    }
}
