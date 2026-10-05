// RestockService.swift
// Every change to Restock: staples and their levels, the needs on the office
// run and the to-order list, checking them off, and one open need per staple
// when two devices race. The notebook's page, the Daybook Assistant, Siri and
// MCP all write through here. Staples are in +Staples, needs in +Needs.
//
// Like OrderService it changes objects and leaves saving to the caller: the
// notebook's page through SaveCoordinator (one save per burst of taps, like
// Orders' −/+), the Assistant through AssistantSave, which then puts what the
// save created into the classroom share.

import CoreData
import Foundation

/// The one writer for staples (`CDSupply`) and needs (`CDOrderItem`).
///
/// A staple has a level and a source. A need is a `CDOrderItem`: a one-off on
/// its own, or a staple's, pointing back at it by `supplyID`. A staple that
/// goes Low or Out gets exactly one open need; checking that need off puts the
/// staple back to Stocked; marking the staple Stocked closes the need (deleted
/// if never asked for, received if it was). Every level change writes a line
/// of history (`CDSupplyTransaction`, `quantityChange` 0).
nonisolated enum RestockService {

    /// What `addStaple` or `addOneOff` found or made.
    struct Added<Object: NSManagedObject> {
        let object: Object
        /// False when the same thing was already there; that is returned
        /// instead, unchanged.
        let isNew: Bool
    }

    /// What the guide edits about a staple (the Edit sheet).
    struct StapleDetails: Equatable {
        var name: String
        var place: String
        var source: RestockSource
        /// The product link, for a staple that is ordered.
        var link: URL?
        var note: String

        init(name: String, place: String = "", source: RestockSource = .office, link: URL? = nil, note: String = "") {
            self.name = name
            self.place = place
            self.source = source
            self.link = link
            self.note = note
        }

        /// The staple as it stands, to start editing from.
        init(_ supply: CDSupply) {
            self.init(
                name: supply.name,
                place: supply.location,
                source: supply.source,
                link: supply.urlString.isEmpty ? nil : URL(string: supply.urlString),
                note: supply.notes
            )
        }
    }

    /// A shelf's staples that live in one place.
    struct PlaceGroup: Identifiable {
        /// The place as the first staple there spells it; "" for none.
        let place: String
        let staples: [CDSupply]

        var id: String { place.foldedKey() }
        var title: String { place.isEmpty ? "No place yet" : place }
    }

    /// What `checkOff` changed, for `undoCheckOff` (while `canUndo`).
    struct CheckOff {
        let need: CDOrderItem
        /// When it was checked off: the need's `receivedAt`, and the
        /// staple's `levelChangedAt` when it put one back to Stocked.
        let checkedAt: Date
        /// The staple put back to Stocked, with what it held before.
        var staple: CDSupply?
        var levelBefore = RestockLevel.stocked
        var changedAtBefore: Date?
        var changedByIDBefore: String?
        var changedByNameBefore = ""
        var history: CDSupplyTransaction?
    }

    // MARK: - Reading

    /// Every staple, by name. `store` limits it to one store: the Assistant
    /// reads the classroom's from the shared store only.
    static func staples(in context: NSManagedObjectContext, store: NSPersistentStore? = nil) -> [CDSupply] {
        let request = CDFetchRequest(CDSupply.self)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        if let store { request.affectedStores = [store] }
        return context.safeFetch(request)
    }

    /// Every need not yet checked off, oldest first.
    static func openNeeds(in context: NSManagedObjectContext, store: NSPersistentStore? = nil) -> [CDOrderItem] {
        let request = CDFetchRequest(CDOrderItem.self)
        request.predicate = NSPredicate(format: "receivedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        if let store { request.affectedStores = [store] }
        return context.safeFetch(request)
    }

    /// The staple's needs not yet checked off, oldest first: one, once
    /// `reconcile` has run.
    static func openNeeds(for supply: CDSupply, in context: NSManagedObjectContext) -> [CDOrderItem] {
        guard let id = supply.id?.uuidString else { return [] }
        return needs(forSupplyID: id, openOnly: true, in: context)
    }

    /// The staple a need restocks, while it still exists.
    static func staple(for need: CDOrderItem, in context: NSManagedObjectContext) -> CDSupply? {
        guard let id = need.supplyID.flatMap(UUID.init(uuidString:)) else { return nil }
        let request = CDFetchRequest(CDSupply.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return context.safeFetch(request).first
    }

    /// A staple's history, newest first: "Low · Ana", "Out", "Restocked", and
    /// any counted change with its reason.
    static func history(for supply: CDSupply, in context: NSManagedObjectContext) -> [CDSupplyTransaction] {
        guard let id = supply.id?.uuidString else { return [] }
        let request = CDFetchRequest(CDSupplyTransaction.self)
        request.predicate = NSPredicate(format: "supplyID ==[c] %@", id)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return context.safeFetch(request)
    }

    /// The ids (upper-cased) of the staples with any history: the saved
    /// lines read as ids alone, and any line still waiting for its save.
    static func stapleIDsWithHistory(
        in context: NSManagedObjectContext,
        store: NSPersistentStore? = nil
    ) -> Set<String> {
        let request = NSFetchRequest<NSDictionary>(entityName: "SupplyTransaction")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["supplyID"]
        request.returnsDistinctResults = true
        request.includesPendingChanges = false
        if let store { request.affectedStores = [store] }
        let rows = (try? context.fetch(request)) ?? []
        var ids = Set(rows.compactMap { ($0["supplyID"] as? String)?.uppercased() })
        for case let entry as CDSupplyTransaction in context.insertedObjects {
            ids.insert(entry.supplyID.uppercased())
        }
        return ids
    }

    /// How many open needs are for the office run and how many are to order,
    /// counted in the store rather than fetched (Today's card, badges).
    static func openNeedCounts(
        in context: NSManagedObjectContext,
        store: NSPersistentStore? = nil
    ) -> (officeRun: Int, toOrder: Int) {
        func count(_ source: RestockSource) -> Int {
            let request = CDFetchRequest(CDOrderItem.self)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                neededPredicate, NSPredicate(format: "sourceRaw == %@", source.rawValue)
            ])
            if let store { request.affectedStores = [store] }
            return (try? context.count(for: request)) ?? 0
        }
        return (count(.office), count(.order))
    }

    /// Staples grouped by where they live, places A to Z and "No place yet"
    /// last; staples by name within each. Places match whatever their case,
    /// and a group shows the spelling most of its staples use (capitals first
    /// on a tie).
    static func shelf(_ staples: [CDSupply]) -> [PlaceGroup] {
        let grouped = Dictionary(grouping: staples) { $0.location.foldedKey() }
        return grouped.values
            .map { members in
                let sorted = members.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                let spellings = Dictionary(grouping: members.map { $0.location.trimmed() }) { $0 }.mapValues(\.count)
                let place = spellings.max { lhs, rhs in
                    lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
                }?.key ?? ""
                return PlaceGroup(place: place, staples: sorted)
            }
            .sorted { lhs, rhs in
                if lhs.place.isEmpty != rhs.place.isEmpty { return !lhs.place.isEmpty }
                return lhs.place.localizedStandardCompare(rhs.place) == .orderedAscending
            }
    }

    /// Whether a need still waits on the classroom: not checked off, and not
    /// asked for (one asked for waits on the office). Office needs are never
    /// asked for, so this only narrows "to order". The badge, Today's card and
    /// the page header all count by it.
    static func isNeeded(_ need: CDOrderItem) -> Bool {
        need.receivedAt == nil && need.requestedAt == nil
    }

    /// `isNeeded` for a fetch.
    static var neededPredicate: NSPredicate { NSPredicate(format: "receivedAt == nil AND requestedAt == nil") }

    // MARK: - Stores

    /// Where a new record goes. Next to `neighbor` once that is saved: a
    /// staple's history must sit in its staple's store, and its need beside
    /// it. Otherwise by role: an assistant's records go straight into the
    /// shared store, where the classroom share is, as her attendance marks do
    /// (`CDAttendanceStore`); the guide's into the private store, from which
    /// `SharedStoreOrphanGuard` shares them. Nil with one store (tests, the
    /// Sample Class), where there is nothing to choose.
    static func destinationStore(
        for role: CDClassroomMembership.ClassroomRole,
        near neighbor: NSManagedObject? = nil,
        in context: NSManagedObjectContext
    ) -> NSPersistentStore? {
        guard let stores = context.persistentStoreCoordinator?.persistentStores, stores.count > 1 else { return nil }
        if let neighbor, !neighbor.objectID.isTemporaryID, let store = neighbor.objectID.persistentStore {
            return store
        }
        let wanted = role == .assistant ? CoreDataStack.sharedConfiguration : CoreDataStack.privateConfiguration
        return stores.first { $0.configurationName == wanted }
    }

    // MARK: - Shared steps

    static func needs(forSupplyID id: String, openOnly: Bool, in context: NSManagedObjectContext) -> [CDOrderItem] {
        let request = CDFetchRequest(CDOrderItem.self)
        request.predicate = openOnly
            ? NSPredicate(format: "receivedAt == nil AND supplyID ==[c] %@", id)
            : NSPredicate(format: "supplyID ==[c] %@", id)
        return context.safeFetch(request).sorted(by: isOlder)
    }

    /// Oldest first by (`createdAt`, `id`): the same order on every device.
    static func isOlder(_ lhs: CDOrderItem, _ rhs: CDOrderItem) -> Bool {
        let left = lhs.createdAt ?? .distantPast
        let right = rhs.createdAt ?? .distantPast
        if left != right { return left < right }
        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
    }

    /// A staple's need: named for it, from its source, pointing back at it.
    @discardableResult
    static func openNeed(
        for supply: CDSupply,
        by author: RestockAuthor,
        at now: Date,
        store: NSPersistentStore?,
        in context: NSManagedObjectContext
    ) -> CDOrderItem {
        if supply.id == nil { supply.id = UUID() }
        let need = CDOrderItem(context: context)
        if let store { context.assign(need, to: store) }
        need.title = supply.name
        need.urlString = supply.urlString
        need.source = supply.source
        need.supplyID = supply.id?.uuidString
        need.quantity = 1
        stampAdded(need, by: author)
        need.createdAt = now
        need.modifiedAt = now
        return need
    }

    /// Closes the needs a restocked staple no longer has: one never asked for
    /// is deleted, one already asked for is marked received.
    static func close(_ needs: [CDOrderItem], at now: Date, in context: NSManagedObjectContext) {
        for need in needs where need.receivedAt == nil {
            if need.stage == .toRequest {
                context.delete(need)
            } else {
                OrderService.setReceived([need], true, at: now)
            }
        }
    }

    /// Writes the staple's current level to its history.
    @discardableResult
    static func recordLevel(
        _ supply: CDSupply,
        by author: RestockAuthor,
        at now: Date,
        store: NSPersistentStore?,
        in context: NSManagedObjectContext
    ) -> CDSupplyTransaction {
        let entry = historyEntry(for: supply, at: now, store: store, in: context)
        entry.quantityChange = 0
        entry.reason = historyReason(for: supply.level, by: author)
        return entry
    }

    static func historyEntry(
        for supply: CDSupply,
        at now: Date,
        store: NSPersistentStore?,
        in context: NSManagedObjectContext
    ) -> CDSupplyTransaction {
        if supply.id == nil { supply.id = UUID() }
        let entry = CDSupplyTransaction(context: context)
        if let store { context.assign(entry, to: store) }
        // Named by `supplyID` only, never through the `supply` relationship:
        // sharing a new history row would take a linked staple along, and a
        // staple already in the classroom share must never be shared again.
        entry.supplyID = supply.id?.uuidString ?? ""
        entry.date = now
        return entry
    }

    static func stampAdded(_ need: CDOrderItem, by author: RestockAuthor) {
        need.addedByID = author.recordName
        need.addedByName = author.stampedName
    }

    /// A web link, cleaned; nil for none or anything that isn't one.
    static func webLink(_ link: URL?) -> String? {
        guard let link, OrderService.isWebURL(link) else { return nil }
        return OrderLinkCleaner.clean(link.absoluteString)
    }
}
