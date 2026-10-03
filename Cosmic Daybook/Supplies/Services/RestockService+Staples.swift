// RestockService+Staples.swift
// Staples: adding, editing and deleting them, their level, and their count.

import CoreData
import Foundation

nonisolated extension RestockService {

    // MARK: - Adding and editing

    /// Adds a staple at `level`. Low or Out opens its need and writes the
    /// first line of its history. Its link is cleaned (`OrderLinkCleaner`).
    /// Returns nil for a blank name, and the staple already called that
    /// (unchanged) rather than a second one.
    static func addStaple(
        _ details: StapleDetails,
        level: RestockLevel = .stocked,
        by author: RestockAuthor,
        at now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> Added<CDSupply>? {
        let name = details.name.trimmed()
        guard !name.isEmpty else { return nil }
        let store = destinationStore(for: author.role, in: context)
        let key = name.foldedKey()
        if let existing = staples(in: context, store: store).first(where: { $0.name.foldedKey() == key }) {
            return Added(object: existing, isNew: false)
        }

        let supply = CDSupply(context: context)
        if let store { context.assign(supply, to: store) }
        let link = webLink(details.link)
        supply.name = name
        supply.location = details.place.trimmed()
        supply.source = details.source
        supply.urlString = link ?? ""
        supply.notes = details.note.trimmed()
        supply.level = level
        supply.createdAt = now
        // Stamped even when Stocked, so the count-to-level launch step
        // (`RestockLevelBackfill`) never judges a staple someone has set.
        stampLevel(supply, by: author, at: now)
        if level.isNeeded {
            recordLevel(supply, by: author, at: now, store: store, in: context)
            openNeed(for: supply, by: author, at: now, store: store, in: context)
        }
        return Added(object: supply, isNew: true)
    }

    /// Edits a staple. Its need not yet asked for follows it (name, link,
    /// source); one already asked for keeps what the office was sent. Returns
    /// whether anything changed.
    @discardableResult
    static func updateStaple(
        _ supply: CDSupply,
        to details: StapleDetails,
        at now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> Bool {
        let trimmed = details.name.trimmed()
        let name = trimmed.isEmpty ? supply.name : trimmed
        let link = webLink(details.link) ?? ""
        let place = details.place.trimmed()
        let note = details.note.trimmed()
        guard supply.name != name || supply.location != place || supply.source != details.source
            || supply.urlString != link || supply.notes != note else { return false }
        supply.name = name
        supply.location = place
        supply.source = details.source
        supply.urlString = link
        supply.notes = note
        supply.modifiedAt = now
        for need in openNeeds(for: supply, in: context) where need.stage == .toRequest {
            need.title = name
            need.urlString = link
            need.source = details.source
            need.modifiedAt = now
        }
        return true
    }

    /// The staple's note ("Add a Note…"). Returns whether it changed.
    @discardableResult
    static func setNote(_ supply: CDSupply, to note: String, at now: Date = Date()) -> Bool {
        let trimmed = note.trimmed()
        guard supply.notes != trimmed else { return false }
        supply.notes = trimmed
        supply.modifiedAt = now
        return true
    }

    /// Deletes a staple and its history. Its need not yet asked for goes too;
    /// any other need of it stays as a one-off, so an order in flight is still
    /// followed to received.
    static func deleteStaple(_ supply: CDSupply, at now: Date = Date(), in context: NSManagedObjectContext) {
        if let id = supply.id?.uuidString {
            for need in needs(forSupplyID: id, openOnly: false, in: context) {
                if need.receivedAt == nil, need.stage == .toRequest {
                    context.delete(need)
                } else {
                    need.supplyID = nil
                    need.modifiedAt = now
                }
            }
        }
        // History is named by `supplyID` (older rows are also linked, and
        // cascade): delete it by id so none is left behind.
        for entry in history(for: supply, in: context) {
            context.delete(entry)
        }
        context.delete(supply)
    }

    /// Sets how many are on hand. Counted staples are for later (Low at
    /// `minimumThreshold`), so a count moves no level. With a reason the
    /// change goes into the staple's history too. Returns whether it changed.
    @discardableResult
    static func setCount(
        _ supply: CDSupply,
        to count: Int,
        reason: String? = nil,
        at now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> Bool {
        let newCount = Int64(max(0, count))
        let change = newCount - supply.currentQuantity
        guard change != 0 else { return false }
        supply.currentQuantity = newCount
        supply.modifiedAt = now
        if let reason = reason?.trimmed(), !reason.isEmpty {
            let store = supply.objectID.isTemporaryID ? nil : supply.objectID.persistentStore
            let entry = historyEntry(for: supply, at: now, store: store, in: context)
            entry.quantityChange = change
            entry.reason = reason
        }
        return true
    }

    // MARK: - Levels

    /// Sets a staple's level, stamps who and when, and writes it to history.
    /// Going Low or Out opens the staple's need (Low → Out keeps the same
    /// one); going Stocked closes it: deleted if never asked for, received if
    /// it was.
    ///
    /// The level a staple already has writes nothing, except that a Low or
    /// Out staple whose need went missing (another device closed it as this
    /// one marked it) gets one again, and Stocked closes any need still open.
    /// Returns whether anything changed.
    @discardableResult
    static func setLevel(
        _ supply: CDSupply,
        to level: RestockLevel,
        by author: RestockAuthor,
        at now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> Bool {
        let open = openNeeds(for: supply, in: context)
        let store = destinationStore(for: author.role, near: supply, in: context)
        guard supply.level != level else {
            if level.isNeeded, open.isEmpty {
                openNeed(for: supply, by: author, at: now, store: store, in: context)
                return true
            }
            if !level.isNeeded, !open.isEmpty {
                close(open, at: now, in: context)
                return true
            }
            return false
        }
        supply.level = level
        stampLevel(supply, by: author, at: now)
        recordLevel(supply, by: author, at: now, store: store, in: context)
        if !level.isNeeded {
            close(open, at: now, in: context)
        } else if open.isEmpty {
            openNeed(for: supply, by: author, at: now, store: store, in: context)
        }
        return true
    }

    /// Who last set the level and when, stamped as attendance marks are.
    static func stampLevel(_ supply: CDSupply, by author: RestockAuthor, at now: Date) {
        supply.levelChangedAt = now
        supply.levelChangedByID = author.recordName
        supply.levelChangedByName = author.stampedName
        supply.modifiedAt = now
    }

    /// The history line for a level change: "Low · Ana", "Out", "Restocked".
    static func historyReason(for level: RestockLevel, by author: RestockAuthor) -> String {
        let what = level == .stocked ? "Restocked" : level.displayName
        let name = author.stampedName
        return name.isEmpty ? what : "\(what) · \(name)"
    }
}
