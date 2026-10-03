import Foundation
import CoreData
import OSLog
import Observation

/// The Restock tab: the classroom's staples by place, the office run, and what
/// the guide is ordering, all from the classroom share.
///
/// Every change goes through `RestockService`, the notebook's writer, so a
/// staple marked Out here opens the same one need the guide's Mac would. Saves
/// go through `AssistantSave`, which puts the records a save created (a level's
/// history line, a new need) into the classroom share. A burst of taps
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
    /// What to grab from the office: every open need from the office, plus
    /// those checked off on this phone since the tab opened (ticked, so a
    /// second tap takes the check-off back).
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

    /// This phone's check-offs since the tab opened, by need, for Undo.
    /// Observed: a row redraws ticked from it.
    private var checkOffs: [NSManagedObjectID: RestockService.CheckOff] = [:]
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// Reloads the tab when the guide's changes arrive from iCloud.
    @ObservationIgnored private var importReloader: RemoteImportReloader?

    let context: NSManagedObjectContext
    private let container: NSPersistentCloudKitContainer?
    let author: RestockAuthor
    private let saveDelay: Duration
    private let now: () -> Date

    /// - Parameters:
    ///   - container: nil for the sample class and tests: their records go into no share.
    ///   - author: who this phone's changes are stamped with.
    ///   - saveDelay: how long a burst of taps waits before it saves.
    init(
        context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?,
        author: RestockAuthor,
        saveDelay: Duration = .milliseconds(800),
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.container = container
        self.author = author
        self.saveDelay = saveDelay
        self.now = now
        self.importReloader = RemoteImportReloader { [weak self] in self?.load() }
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
    /// one open need per staple, when two devices each opened one at once
    /// (`RestockService.reconcile`): on the tab's appear and after imports,
    /// never in a loop.
    func load(reconcile: Bool = true) {
        if reconcile, RestockService.reconcile(in: context, store: store) > 0 {
            save()
        }
        let staples = RestockService.staples(in: context, store: store)
        shelf = RestockService.shelf(staples)
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
        guard RestockService.setLevel(staple, to: level, by: author, at: now(), in: context) else { return }
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

    /// The staple whose name is exactly `text` (any case or accents), for
    /// the "We need…" sheet: naming one marks it Out instead of adding a
    /// second need for it.
    func staple(named text: String) -> CDSupply? {
        let key = text.foldedKey()
        guard !key.isEmpty else { return nil }
        return staples.first { $0.name.foldedKey() == key }
    }

    // MARK: - The office run

    func isCheckedOff(_ need: CDOrderItem) -> Bool {
        checkOffs[need.objectID] != nil
    }

    /// Checks a need off (a staple's goes back to Stocked, for everyone), or
    /// takes back this phone's check-off of it.
    func toggleCheckOff(_ need: CDOrderItem) {
        if let checkOff = checkOffs.removeValue(forKey: need.objectID) {
            RestockService.undoCheckOff(checkOff, at: now(), in: context)
        } else {
            guard let checkOff = RestockService.checkOff(need, by: author, at: now(), in: context) else { return }
            checkOffs[need.objectID] = checkOff
        }
        changed()
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
        if let staple = staple(named: text) {
            setLevel(staple, to: .out)
            flush()
            return .markedStaple
        }
        let link = Self.pastedLink(text)
        guard let added = RestockService.addOneOff(
            title: link == nil ? text : "",
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

    /// A pasted web link ("amazon.com/dp/…", "https://…"); nil for a name.
    /// A bare word isn't a link: "Glue" would otherwise read as https://Glue.
    static func pastedLink(_ text: String) -> URL? {
        let trimmed = text.trimmed()
        guard trimmed.contains("://") || trimmed.contains(".") else { return nil }
        return OrderService.webURL(from: trimmed)
    }

    // MARK: - Who and when

    /// "You · 8:12 AM", "Your guide · Oct 1": who set a Low or Out staple's
    /// level, and when. Nil for a Stocked one.
    func markedBy(_ staple: CDSupply) -> String? {
        guard staple.level.isNeeded, let at = staple.levelChangedAt else { return nil }
        return "\(who(staple).capitalizedFirst) · \(Self.when(at, now: now()))"
    }

    /// The hold menu's header: "Out since Oct 1, marked by your guide ·
    /// Bathrooms · From the office", and the note on a line of its own.
    func menuHeader(_ staple: CDSupply) -> String {
        var parts: [String] = []
        if let at = staple.levelChangedAt {
            let when = Self.when(at, now: now())
            parts.append(staple.level.isNeeded
                ? "\(staple.level.displayName) since \(when), marked by \(who(staple))"
                : "Restocked \(when) by \(who(staple))")
        } else {
            parts.append(staple.level.displayName)
        }
        if !staple.location.isEmpty { parts.append(staple.location) }
        parts.append(staple.source == .office ? "From the office" : "Ordered")
        let line = parts.joined(separator: " · ")
        return staple.notes.isEmpty ? line : "\(line)\n\(staple.notes)"
    }

    /// The line under an office-run row: "Bathrooms · you, 8:12 AM" for a
    /// staple, "Added by your guide" for a one-off.
    func runDetail(_ need: CDOrderItem) -> String {
        if let staple = staple(for: need) {
            var parts: [String] = []
            if !staple.location.isEmpty { parts.append(staple.location) }
            if staple.level.isNeeded, let at = staple.levelChangedAt {
                parts.append("\(who(staple)), \(Self.when(at, now: now()))")
            }
            return parts.isEmpty ? "From the shelf" : parts.joined(separator: " · ")
        }
        return "Added by \(author.reads(changedByID: need.addedByID, name: need.addedByName))"
    }

    /// The staple a need restocks, while it exists.
    func staple(for need: CDOrderItem) -> CDSupply? {
        RestockService.staple(for: need, in: context)
    }

    /// "Low · not asked yet", "Asked Sep 30 · waiting 3 days": where one of
    /// the guide's orders stands.
    func orderStatus(_ need: CDOrderItem) -> String {
        Self.orderStatus(need, stapleLevel: staple(for: need)?.level, now: now())
    }

    static func orderStatus(_ need: CDOrderItem, stapleLevel: RestockLevel?, now: Date) -> String {
        switch need.stage {
        case .toRequest:
            if let stapleLevel, stapleLevel.isNeeded { return "\(stapleLevel.displayName) · not asked yet" }
            return "Not asked yet"
        case .requested:
            guard let asked = need.requestedAt else { return "Asked" }
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: asked), to: calendar.startOfDay(for: now)
            ).day ?? 0
            let date = asked.formatted(.dateTime.month(.abbreviated).day())
            switch days {
            case ...0: return "Asked today"
            case 1: return "Asked \(date) · waiting 1 day"
            default: return "Asked \(date) · waiting \(days) days"
            }
        case .confirmed:
            return need.confirmedAt.map { "Confirmed \($0.formatted(.dateTime.month(.abbreviated).day()))" }
                ?? "Confirmed"
        case .received:
            return "Received"
        }
    }

    private func who(_ staple: CDSupply) -> String {
        author.reads(changedByID: staple.levelChangedByID, name: staple.levelChangedByName)
    }

    /// The time for today ("8:12 AM"), the date before ("Oct 1").
    static func when(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Saving

    /// After a change: redraw at once, save once the burst of taps ends.
    private func changed() {
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
        guard context.hasChanges else { return }
        save()
    }

    /// Saves, and puts what the save created into the classroom share.
    private func save() {
        let created = context.insertedObjects.filter { Self.restockEntities.contains($0.entity.name ?? "") }
        // A failed save is this phone's own store refusing the change, not
        // the network. The change stays pending, so the next save tries again.
        guard AssistantSave.save(context, container: container, created: Array(created)) else {
            Self.logger.error("Saving a Restock change failed")
            errorMessage = "Couldn't save that change. Try again."
            return
        }
        errorMessage = nil
    }

    /// The types Restock writes, all in the classroom share.
    static let restockEntities: Set<String> = ["Supply", "SupplyTransaction", "OrderItem"]
}

extension String {
    /// "your guide" → "Your guide".
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
