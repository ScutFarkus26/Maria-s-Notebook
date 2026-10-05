// RestockService+Needs.swift
// Needs: one-offs, checking off (and taking it back), the request stages, and
// keeping one open need per staple when two devices race.

import CoreData
import Foundation

nonisolated extension RestockService {

    // MARK: - One-offs

    /// Adds a one-off need. A link makes it an order unless `source` says
    /// otherwise; the link is cleaned (`OrderLinkCleaner`) and a title that
    /// came with it shortened. Without a link the title is required, and the
    /// need is from the office. The same link, or with no link the same name
    /// from the same source, already waiting is returned instead of a second
    /// copy (a staple's open need counts). Nil when there is nothing to add.
    static func addOneOff(
        title: String,
        link: URL? = nil,
        quantity: Int = 1,
        source: RestockSource? = nil,
        note: String = "",
        by author: RestockAuthor,
        at now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> Added<CDOrderItem>? {
        let cleanLink = webLink(link)
        let name = cleanLink == nil ? title.trimmed() : OrderLinkCleaner.shortTitle(title)
        guard !name.isEmpty || cleanLink != nil else { return nil }
        let source = source ?? (cleanLink == nil ? .office : .order)
        let store = destinationStore(for: author.role, in: context)
        if let waiting = waitingNeed(link: cleanLink, name: name, source: source, store: store, in: context) {
            return Added(object: waiting, isNew: false)
        }

        let need = CDOrderItem(context: context)
        if let store { context.assign(need, to: store) }
        need.title = name
        need.urlString = cleanLink ?? ""
        need.quantity = OrderService.clampedQuantity(quantity)
        need.notes = note.trimmed()
        need.source = source
        stampAdded(need, by: author)
        need.createdAt = now
        need.modifiedAt = now
        return Added(object: need, isNew: true)
    }

    /// An open need already standing for this one: the same link (both
    /// cleaned), or for a need with no link, the same name from the same source.
    private static func waitingNeed(
        link: String?,
        name: String,
        source: RestockSource,
        store: NSPersistentStore?,
        in context: NSManagedObjectContext
    ) -> CDOrderItem? {
        let waiting = openNeeds(in: context, store: store)
        if let link {
            let key = OrderService.normalized(link)
            return waiting.first { OrderService.normalized(OrderLinkCleaner.clean($0.urlString)) == key }
        }
        let key = name.foldedKey()
        return waiting.first {
            $0.urlString.trimmed().isEmpty && $0.source == source && $0.title.foldedKey() == key
        }
    }

    /// Fills in a need's title from its page, shortened, unless one was typed
    /// meanwhile. Returns whether it changed.
    @discardableResult
    static func applyFetchedTitle(_ title: String, to need: CDOrderItem, at now: Date = Date()) -> Bool {
        guard !need.isDeleted, need.managedObjectContext != nil, need.title.trimmed().isEmpty else { return false }
        let short = OrderLinkCleaner.shortTitle(title)
        guard !short.isEmpty else { return false }
        need.title = short
        need.modifiedAt = now
        return true
    }

    // MARK: - Checking off

    /// Checks a need off: it's received, and its staple goes back to Stocked
    /// (a duplicate need of that staple is closed with it). Nil when it was
    /// already checked off. Keep the result for `undoCheckOff`.
    @discardableResult
    static func checkOff(
        _ need: CDOrderItem,
        by author: RestockAuthor,
        at now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> CheckOff? {
        guard need.receivedAt == nil else { return nil }
        var result = CheckOff(need: need, checkedAt: now)
        OrderService.setReceived([need], true, at: now)
        guard let supply = staple(for: need, in: context) else { return result }
        close(openNeeds(for: supply, in: context), at: now, in: context)
        guard supply.level != .stocked else { return result }
        result.staple = supply
        result.levelBefore = supply.level
        result.changedAtBefore = supply.levelChangedAt
        result.changedByIDBefore = supply.levelChangedByID
        result.changedByNameBefore = supply.levelChangedByName
        supply.level = .stocked
        stampLevel(supply, by: author, at: now)
        let store = destinationStore(for: author.role, near: supply, in: context)
        result.history = recordLevel(supply, by: author, at: now, store: store, in: context)
        return result
    }

    /// Whether a check-off can still be taken back: nothing has changed since,
    /// here or on another device. The need is still received from that very
    /// check-off, and the staple it put back to Stocked still stands as it
    /// left it. Otherwise Undo would reopen a need someone has since dealt
    /// with, set back a level someone has since set, and delete the history
    /// line every device already has.
    static func canUndo(_ checkOff: CheckOff) -> Bool {
        let need = checkOff.need
        guard !need.isDeleted, need.managedObjectContext != nil,
              sameMoment(need.receivedAt, checkOff.checkedAt) else { return false }
        guard let supply = checkOff.staple else { return true }
        return !supply.isDeleted && supply.managedObjectContext != nil && supply.level == .stocked
            && sameMoment(supply.levelChangedAt, checkOff.checkedAt)
    }

    /// The same stamp, allowing for CloudKit keeping dates to the millisecond.
    private static func sameMoment(_ date: Date?, _ other: Date) -> Bool {
        guard let date else { return false }
        return abs(date.timeIntervalSince(other)) < 0.01
    }

    /// Takes back a check-off: the need is open again, and its staple returns
    /// to the level it had. Only while nothing has changed since (`canUndo`);
    /// returns whether it did.
    @discardableResult
    static func undoCheckOff(_ checkOff: CheckOff, at now: Date = Date(), in context: NSManagedObjectContext) -> Bool {
        guard canUndo(checkOff) else { return false }
        let need = checkOff.need
        OrderService.setReceived([need], false, at: now)
        if let supply = checkOff.staple {
            supply.level = checkOff.levelBefore
            supply.levelChangedAt = checkOff.changedAtBefore
            supply.levelChangedByID = checkOff.changedByIDBefore
            supply.levelChangedByName = checkOff.changedByNameBefore
            supply.modifiedAt = now
        }
        if let history = checkOff.history, !history.isDeleted {
            context.delete(history)
        }
        return true
    }

    /// Deletes needs. An open need of a staple going means nothing is needed
    /// after all, so the staple goes back to Stocked: a Low or Out staple
    /// always has its one open need.
    static func removeNeeds(
        _ needs: [CDOrderItem],
        by author: RestockAuthor,
        at now: Date = Date(),
        in context: NSManagedObjectContext
    ) {
        var staples: [CDSupply] = []
        for need in needs {
            if need.receivedAt == nil, let supply = staple(for: need, in: context) {
                staples.append(supply)
            }
            context.delete(need)
        }
        for supply in staples where supply.level.isNeeded && openNeeds(for: supply, in: context).isEmpty {
            setLevel(supply, to: .stocked, by: author, at: now, in: context)
        }
    }

    // MARK: - Stages (through OrderService)

    /// How many to fetch or order, 1–999.
    static func setQuantity(_ need: CDOrderItem, to quantity: Int, at now: Date = Date()) {
        OrderService.setQuantity(need, to: quantity, at: now)
    }

    /// Marks needs to order as asked for in one request. Only the guide sends
    /// the request email. Needs from the office are never asked for, so
    /// `OrderService` leaves them out.
    static func markRequested(_ needs: [CDOrderItem], from recipient: String, at now: Date = Date()) {
        OrderService.markRequested(needs, from: recipient, at: now)
    }

    static func markConfirmed(_ needs: [CDOrderItem], at now: Date = Date()) {
        OrderService.markConfirmed(needs, at: now)
    }

    static func clearConfirmation(_ needs: [CDOrderItem], at now: Date = Date()) {
        OrderService.clearConfirmation(needs, at: now)
    }

    /// Puts needs back on the to-request list. A received one is open again,
    /// as `reopen` does.
    static func moveBackToRequest(
        _ needs: [CDOrderItem],
        by author: RestockAuthor,
        at now: Date = Date(),
        in context: NSManagedObjectContext
    ) {
        let received = needs.filter { $0.receivedAt != nil }
        OrderService.moveBackToRequest(needs, at: now)
        restockedAgain(received, by: author, at: now, in: context)
    }

    /// Takes back "received" without a check-off to undo (MCP's
    /// not_received): the need is open again, and a staple it had restocked
    /// goes back to Low, so the shelf and the lists agree.
    static func reopen(
        _ needs: [CDOrderItem],
        by author: RestockAuthor,
        at now: Date = Date(),
        in context: NSManagedObjectContext
    ) {
        let received = needs.filter { $0.receivedAt != nil }
        OrderService.setReceived(received, false, at: now)
        restockedAgain(received, by: author, at: now, in: context)
    }

    /// The staples of needs just reopened: still on the shelf as Stocked,
    /// they're Low again, keeping the reopened need as their one need.
    private static func restockedAgain(
        _ reopened: [CDOrderItem],
        by author: RestockAuthor,
        at now: Date,
        in context: NSManagedObjectContext
    ) {
        for need in reopened {
            guard let supply = staple(for: need, in: context), !supply.level.isNeeded else { continue }
            setLevel(supply, to: .low, by: author, at: now, in: context)
        }
    }

    // MARK: - Two devices at once

    /// How long a staple's level must have stood before `reconcile` opens the
    /// need it lacks: until then the need may still be on its way from the
    /// device that set the level.
    static let settledAfter: TimeInterval = 5 * 60

    /// Two devices can each open a need for the same staple before either
    /// syncs. Keeps the oldest by (`createdAt`, `id`), so every device keeps
    /// the same one, and deletes the rest; if only a newer copy had been asked
    /// for, the one kept takes over its request, so the order is still
    /// followed.
    ///
    /// It also mends one way a staple's level and its need fall out of step
    /// across devices (one checks the need off as another marks the staple
    /// Out): a Low or Out staple with no open need gets one, once its level
    /// has stood `settledAfter`. The need is stamped as added by whoever set
    /// the level, and writes no history (setting the level wrote that). The
    /// other way round, a Stocked staple with an open need, is left alone:
    /// another device's half-arrived import could make closing it wrong.
    ///
    /// Run it after remote-change imports and when the page appears, never in
    /// a loop: a second run finds nothing. Returns how many needs it deleted
    /// or opened; the caller saves.
    @discardableResult
    static func reconcile(
        in context: NSManagedObjectContext,
        store: NSPersistentStore? = nil,
        now: Date = Date()
    ) -> Int {
        let request = CDFetchRequest(CDOrderItem.self)
        request.predicate = NSPredicate(format: "receivedAt == nil AND supplyID != nil AND supplyID != %@", "")
        if let store { request.affectedStores = [store] }
        let byStaple = Dictionary(grouping: context.safeFetch(request)) { ($0.supplyID ?? "").uppercased() }
        var removed = 0
        for needs in byStaple.values where needs.count > 1 {
            let ordered = needs.sorted(by: isOlder)
            guard let kept = ordered.first else { continue }
            let extras = ordered.dropFirst()
            if kept.requestedAt == nil, let asked = extras.first(where: { $0.requestedAt != nil }) {
                kept.requestID = asked.requestID
                kept.requestedFrom = asked.requestedFrom
                kept.requestedAt = asked.requestedAt
                kept.confirmedAt = asked.confirmedAt
                kept.modifiedAt = asked.modifiedAt
            }
            for extra in extras {
                context.delete(extra)
                removed += 1
            }
        }
        return removed + openMissingNeeds(besides: Set(byStaple.keys), store: store, now: now, in: context)
    }

    /// Opens a need for each settled Low or Out staple whose id isn't among
    /// `open` (upper-cased): beside the staple, as `setLevel` would.
    private static func openMissingNeeds(
        besides open: Set<String>,
        store: NSPersistentStore?,
        now: Date,
        in context: NSManagedObjectContext
    ) -> Int {
        let request = CDFetchRequest(CDSupply.self)
        request.predicate = NSPredicate(
            // No date (an older build set the level) counts as long settled.
            format: "levelRaw IN %@ AND (levelChangedAt == nil OR levelChangedAt <= %@)",
            [RestockLevel.low.rawValue, RestockLevel.out.rawValue],
            now.addingTimeInterval(-settledAfter) as NSDate
        )
        if let store { request.affectedStores = [store] }
        var opened = 0
        for supply in context.safeFetch(request) {
            guard let id = supply.id?.uuidString.uppercased(), !open.contains(id) else { continue }
            let name = supply.levelChangedByName.trimmed()
            let setter = RestockAuthor(
                role: name.isEmpty ? .leadGuide : .assistant, recordName: supply.levelChangedByID, name: name
            )
            let store = destinationStore(for: setter.role, near: supply, in: context)
            openNeed(for: supply, by: setter, at: now, store: store, in: context)
            opened += 1
        }
        return opened
    }
}
