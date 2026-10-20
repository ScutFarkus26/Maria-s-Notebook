import Foundation
import CoreData

// The Restock tab's model on the app's stack, and what it reads without
// changing anything: its store, the staples by name for "We need…", a
// staple's history, and what an add did.

extension AssistantRestockModel {

    /// The tab's model on the app's stack: this phone's assistant, with the
    /// classroom's owner and everyone's names, as they are at each change.
    /// The guide's name is the one he set in the classroom's list, then
    /// `guideName` (Apple's name for the share's owner, display only).
    static func live(
        context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?,
        guideName: @escaping @MainActor () -> String? = { nil }
    ) -> AssistantRestockModel {
        AssistantRestockModel(context: context, container: container, author: {
            RestockAuthor.assistant(in: context)
                .reading(ClassroomNames.snapshot(in: context).fallingBack(toGuideName: guideName()))
        })
    }

    /// The classroom share's store. On an Apple Account that also keeps a
    /// Cosmic Daybook of its own, the private store holds that notebook's
    /// supplies, which aren't this class's. Nil with one store (the sample
    /// class, tests), which holds only the class.
    var store: NSPersistentStore? {
        context.persistentStoreCoordinator?.persistentStores.first {
            $0.configurationName == CoreDataStack.sharedConfiguration
        }
    }

    /// Every staple, for the "We need…" sheet's match.
    var staples: [CDSupply] { shelf.flatMap(\.staples) }

    /// The staple's history, newest first.
    func history(for staple: CDSupply) -> [CDSupplyTransaction] {
        RestockService.history(for: staple, in: context)
    }

    /// The staple whose name is exactly `text` (any case or accents, without
    /// a closing period), for the "We need…" sheet: naming one marks it Out
    /// instead of adding a second need for it. A staple the guide has just
    /// deleted isn't one: the text becomes a one-off rather than marking
    /// nothing and closing as if it worked (bug hunt 2026-10-20 review).
    func staple(named text: String) -> CDSupply? {
        let key = Self.entry(text).foldedKey()
        guard !key.isEmpty else { return nil }
        return staples.first { !Self.isGone($0) && $0.name.foldedKey() == key }
    }

    /// The staple is gone: deleted here, or by the guide with the delete
    /// arrived (no context left).
    static func isGone(_ staple: CDSupply) -> Bool {
        staple.isDeleted || staple.managedObjectContext == nil
    }

    /// What "We need…" did.
    enum AddResult: Equatable {
        /// A new need on the office run or the order list.
        case added
        /// The same thing was already waiting; nothing was added.
        case alreadyListed
        /// It's a staple, which is now marked Out.
        case markedStaple
        /// The same thing was waiting, and now asks for the larger count.
        case updatedQuantity
        /// Nothing to add: no name.
        case nothing
        /// The phone couldn't save it (`errorMessage` says so). The change
        /// waits in the context; the sheet's next add replaces it with what
        /// the sheet says then, and tries the save again.
        case notSaved
    }

}
