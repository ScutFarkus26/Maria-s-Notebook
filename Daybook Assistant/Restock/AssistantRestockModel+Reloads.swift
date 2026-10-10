import Foundation
import CoreData

// When the Restock tab reloads (imports from iCloud, while the app is on
// screen), and whether a reload redraws it: only when something it shows
// has changed.

extension AssistantRestockModel {

    /// Reloads the tab whenever an import into the classroom's store
    /// finishes, until the calling task is cancelled.
    func followRemoteImports(into storeIdentifier: String) async {
        await importReloader?.observeImports(into: storeIdentifier)
    }

    /// The app left the screen (`isActive` false) or came back to it
    /// (`RestockFollowsScene`). Away, an import doesn't reload the tab; back,
    /// the return's own `load()` shows it, and a reload held meanwhile is
    /// dropped rather than run as a second one.
    func followScene(isActive: Bool) {
        if isActive {
            importReloader?.appReturned()
        } else {
            importReloader?.appLeft()
        }
    }

    /// Everything the tab's tiles and rows read, copied out as values: the
    /// staples and needs in the order shown with every stored value (a tile
    /// reads its staple straight off the managed object, which an import
    /// changes in place), the staples with history, the ticked rows, who's
    /// reading (the names), and the day (a time today reads "8:12 AM", one
    /// before "Oct 1"; "waiting 3 days" counts days).
    struct Shown: Equatable {
        var staples: [NSManagedObjectID]
        var needs: [NSManagedObjectID]
        var values: [NSDictionary]
        var withHistory: Set<String>
        var ticked: Set<NSManagedObjectID>
        var author: RestockAuthor
        var day: Date
    }

    /// What the tab shows now.
    func shownNow() -> Shown {
        let staples = self.staples
        let needs = officeRun + ordering
        let objects = (staples as [NSManagedObject]) + (needs as [NSManagedObject])
        return Shown(
            staples: staples.map(\.objectID),
            needs: needs.map(\.objectID),
            values: objects.map { object in
                object.dictionaryWithValues(forKeys: Array(object.entity.attributesByName.keys)) as NSDictionary
            },
            withHistory: staplesWithHistory,
            ticked: Set(officeRun.filter(isCheckedOff).map(\.objectID)),
            author: author,
            day: Calendar.current.startOfDay(for: now())
        )
    }

    /// The same places, in the same order, each with the same staples.
    static func sameShelf(_ lhs: [RestockService.PlaceGroup], _ rhs: [RestockService.PlaceGroup]) -> Bool {
        lhs.map(\.place) == rhs.map(\.place) && lhs.map(\.staples) == rhs.map(\.staples)
    }
}
