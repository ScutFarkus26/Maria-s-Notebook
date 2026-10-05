import Foundation
import CoreData
import OSLog
import Observation

/// The Restock tab: the classroom's staples by place, the office run, and what
/// the guide is ordering, all from the classroom share.
///
/// Every change goes through `RestockService`, the notebook's writer, so a
/// staple marked Out here opens the same one need the guide's Mac would. Saves
/// go through `AssistantSave`, which puts the records this tab created (a
/// level's history line, a new need) into the classroom share. A burst of taps
/// (Stocked → Low → Out) saves once, `saveDelay` after the last; leaving the
/// app or the tab saves at once (`flush`).
///
/// A tap only ever says "running out": Stocked → Low → Out. Out goes back to
/// Stocked from the office run's check-off, or from the hold menu.
@MainActor
@Observable
final class AssistantRestockModel {

    private static let logger = Logger.app(category: "restock")

    /// The staples by place, places A to Z and "No place yet" last.
    private(set) var shelf: [RestockService.PlaceGroup] = []
    /// The same staples by upper-cased id, so a need's row finds its staple
    /// without a fetch on every redraw.
    @ObservationIgnored private var staplesByID: [String: CDSupply] = [:]
    /// The staples (by upper-cased id) with a line of history: read on each
    /// load, and added to as this phone writes one. A Stocked staple with
    /// none hasn't changed since it was put on the shelf.
    @ObservationIgnored private(set) var staplesWithHistory: Set<String> = []
    /// What to grab from the office: every open need from the office, plus
    /// those checked off on this phone since she came to the tab (ticked, so
    /// a second tap takes the check-off back).
    private(set) var officeRun: [CDOrderItem] = []
    /// What the guide orders: open needs to order, oldest first. Read-only here.
    private(set) var ordering: [CDOrderItem] = []
    /// Open needs from the office: the tab's badge.
    private(set) var officeRunCount = 0
    /// Bumped by every change and reload, so tiles that read their staple's
    /// level straight off the managed object redraw.
    private(set) var revision = 0
    /// The last failed save, until one works.
    private(set) var errorMessage: String?

    /// This phone's check-offs since she came to the tab, for Undo, by the
    /// need's `id`: the first save gives a new need another objectID, never
    /// another id. Forgotten when she comes back to the tab or the app
    /// (`forgetCheckOffs`). Observed: a row redraws ticked from it.
    private var checkOffs: [UUID: RestockService.CheckOff] = [:]
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// The Restock records made here since this tab's last save, to put into
    /// the classroom share once a save gives them permanent IDs. Noted as
    /// they're made rather than read off `insertedObjects` at the save: the
    /// attendance grid saves the same context, and a record its save wrote
    /// never went into the share.
    @ObservationIgnored private var createdSinceSave: Set<NSManagedObject> = []
    /// Reloads the tab when the guide's changes arrive from iCloud.
    @ObservationIgnored private var importReloader: RemoteImportReloader?

    let context: NSManagedObjectContext
    /// Who this phone's changes are stamped with, and who "you" are when
    /// they're read back. Read again on every load and before every change,
    /// so a name she gives after the tab opened (or the record name iCloud
    /// sends later) counts at once.
    @ObservationIgnored private(set) var author: RestockAuthor
    private let currentAuthor: @MainActor () -> RestockAuthor
    private let saveDelay: Duration
    /// The time now; tests fix it.
    let now: () -> Date
    private let saveChanges: Save

    /// Saves the context and puts `created` into the classroom share; true
    /// when the save worked. Tests pass their own.
    typealias Save = @MainActor (_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool

    /// - Parameters:
    ///   - container: nil for the sample class and tests: their records go into no share.
    ///   - author: who this phone's changes are stamped with, as she is at the moment.
    ///   - saveDelay: how long a burst of taps waits before it saves.
    ///   - save: nil saves through `AssistantSave`.
    init(
        context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?,
        author: @escaping @MainActor () -> RestockAuthor,
        saveDelay: Duration = .milliseconds(800),
        now: @escaping () -> Date = Date.init,
        save: Save? = nil
    ) {
        self.context = context
        self.currentAuthor = author
        self.author = author()
        self.saveDelay = saveDelay
        self.now = now
        self.saveChanges = save ?? { context, created in
            AssistantSave.save(context, container: container, created: created)
        }
        self.importReloader = RemoteImportReloader { [weak self] in self?.load() }
    }

    /// The tab's model on the app's stack: this phone's assistant, with the
    /// classroom's owner, as they are at each change.
    static func live(
        context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?
    ) -> AssistantRestockModel {
        AssistantRestockModel(context: context, container: container, author: { RestockAuthor.assistant(in: context) })
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

    // MARK: - Loading

    /// Reads the shelf and the needs again. With `reconcile` it first keeps
    /// one open need per staple, when two devices each opened one at once,
    /// and opens the need a settled Low or Out staple lacks
    /// (`RestockService.reconcile`): on the tab's appear and after imports,
    /// never in a loop.
    func load(reconcile: Bool = true) {
        author = currentAuthor()
        if reconcile, RestockService.reconcile(in: context, store: store, now: now()) > 0 {
            save()
        }
        let staples = RestockService.staples(in: context, store: store)
        shelf = RestockService.shelf(staples)
        staplesByID = Dictionary(
            staples.compactMap { staple in staple.id.map { ($0.uuidString.uppercased(), staple) } },
            uniquingKeysWith: { first, _ in first }
        )
        staplesWithHistory = RestockService.stapleIDsWithHistory(in: context, store: store)
        AssistantRestockVocabulary.refresh(for: staples)
        refreshNeeds()
    }

    /// Reloads the tab whenever an import into the classroom's store
    /// finishes, until the calling task is cancelled.
    func followRemoteImports(into storeIdentifier: String) async {
        await importReloader?.observeImports(into: storeIdentifier)
    }

    /// The needs again, without refetching the shelf: a change made here
    /// opens and closes needs, but never adds or removes a staple.
    private func refreshNeeds() {
        let open = RestockService.openNeeds(in: context, store: store)
        ordering = open.filter { $0.source == .order }
        let run = open.filter { $0.source == .office }
        officeRunCount = run.count
        // Ticked here and still checked off: kept in place on the list.
        checkOffs = checkOffs.filter { _, checkOff in
            let need = checkOff.need
            return !need.isDeleted && need.managedObjectContext != nil && need.receivedAt != nil
        }
        officeRun = (run + checkOffs.values.map(\.need)).sorted(by: RestockService.isOlder)
        revision &+= 1
    }

    // MARK: - The shelf

    /// A tap on a staple's tile: Stocked → Low → Out. Returns false on Out,
    /// where a tap does nothing and the tile says to hold for more.
    @discardableResult
    func tap(_ staple: CDSupply) -> Bool {
        guard let next = staple.level.afterTap else { return false }
        setLevel(staple, to: next)
        return true
    }

    /// The hold menu's We have plenty / Running low / Out.
    func setLevel(_ staple: CDSupply, to level: RestockLevel) {
        author = currentAuthor()
        let before = staple.level
        guard RestockService.setLevel(staple, to: level, by: author, at: now(), in: context) else { return }
        if staple.level != before { notedHistory(for: staple) }
        changed()
    }

    /// The hold menu's Add a Note… (empty text removes it).
    func setNote(_ text: String?, for staple: CDSupply) {
        guard RestockService.setNote(staple, to: text ?? "", at: now()) else { return }
        changed()
    }

    /// The staple's history, newest first.
    func history(for staple: CDSupply) -> [CDSupplyTransaction] {
        RestockService.history(for: staple, in: context)
    }

    /// The staple whose name is exactly `text` (any case or accents, without
    /// a closing period), for the "We need…" sheet: naming one marks it Out
    /// instead of adding a second need for it.
    func staple(named text: String) -> CDSupply? {
        let key = Self.entry(text).foldedKey()
        guard !key.isEmpty else { return nil }
        return staples.first { $0.name.foldedKey() == key }
    }

    // MARK: - The office run

    func isCheckedOff(_ need: CDOrderItem) -> Bool {
        need.id.map { checkOffs[$0] != nil } ?? false
    }

    /// Checks a need off (a staple's goes back to Stocked, for everyone), or
    /// takes back this phone's check-off of it, while nothing has changed
    /// since (`RestockService.canUndo`); once something has, the tick just
    /// goes.
    func toggleCheckOff(_ need: CDOrderItem) {
        author = currentAuthor()
        if let id = need.id, let checkOff = checkOffs.removeValue(forKey: id) {
            RestockService.undoCheckOff(checkOff, at: now(), in: context)
        } else {
            guard let checkOff = RestockService.checkOff(need, by: author, at: now(), in: context) else { return }
            // Every need carries an id from the day it's made; one that
            // somehow didn't gets one, so its tick can be found again.
            let id = need.id ?? UUID()
            if need.id == nil { need.id = id }
            checkOffs[id] = checkOff
            if let staple = checkOff.staple { notedHistory(for: staple) }
        }
        changed()
    }

    /// The staple a need restocks, while it exists.
    func staple(for need: CDOrderItem) -> CDSupply? {
        guard let id = need.supplyID?.uppercased(), let staple = staplesByID[id], !staple.isDeleted else { return nil }
        return staple
    }

    /// The tab is back on screen, or the app back in the foreground: this
    /// phone's check-offs are done with. Their ticked rows go, and with them
    /// an Undo that days later would take back a restock long since shelved.
    func forgetCheckOffs() {
        guard !checkOffs.isEmpty else { return }
        checkOffs.removeAll()
        refreshNeeds()
    }

    // MARK: - We need…

    /// What "We need…" did.
    enum AddResult: Equatable {
        /// A new need on the office run or the order list.
        case added
        /// The same thing was already waiting; nothing was added.
        case alreadyListed
        /// It's a staple, which is now marked Out.
        case markedStaple
        /// Nothing to add: no name.
        case nothing
    }

    /// Adds a one-off: from the office or to order, `quantity` of it. A pasted
    /// link becomes the need's link. A staple's name marks the staple Out.
    @discardableResult
    func addNeed(_ text: String, source: RestockSource, quantity: Int) -> AddResult {
        let entry = Self.entry(text)
        if let staple = staple(named: entry) {
            setLevel(staple, to: .out)
            flush()
            return .markedStaple
        }
        author = currentAuthor()
        let link = Self.pastedLink(entry)
        guard let added = RestockService.addOneOff(
            title: link == nil ? entry : "",
            link: link,
            quantity: quantity,
            source: source,
            by: author,
            at: now(),
            in: context
        ) else { return .nothing }
        guard added.isNew else { return .alreadyListed }
        changed()
        // The sheet closes on it: save now rather than after a burst.
        flush()
        return .added
    }

    // MARK: - Saving

    /// After a change: redraw at once, save once the burst of taps ends.
    private func changed() {
        noteCreated()
        refreshNeeds()
        pendingSave?.cancel()
        let delay = saveDelay
        pendingSave = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            self?.flush()
        }
    }

    /// Saves anything waiting now: the app or the tab is going away.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard context.hasChanges || !createdSinceSave.isEmpty else { return }
        save()
    }

    /// Saves, and puts what this tab created into the classroom share, even
    /// when another save already wrote it.
    private func save() {
        noteCreated()
        let created = createdSinceSave.filter { !$0.isDeleted && $0.managedObjectContext != nil }
        // A failed save is this phone's own store refusing the change, not
        // the network. The change stays pending, so the next save tries again.
        guard saveChanges(context, Array(created)) else {
            Self.logger.error("Saving a Restock change failed")
            errorMessage = "Couldn't save that change. Try again."
            return
        }
        createdSinceSave.removeAll()
        errorMessage = nil
    }

    /// Notes the Restock records waiting in the context for their first save.
    private func noteCreated() {
        for object in context.insertedObjects where Self.restockEntities.contains(object.entity.name ?? "") {
            createdSinceSave.insert(object)
        }
    }

    /// A level change made here wrote the staple a line of history.
    private func notedHistory(for staple: CDSupply) {
        if let id = staple.id?.uuidString.uppercased() { staplesWithHistory.insert(id) }
    }

    /// The types Restock writes, all in the classroom share.
    static let restockEntities: Set<String> = ["Supply", "SupplyTransaction", "OrderItem"]
}
