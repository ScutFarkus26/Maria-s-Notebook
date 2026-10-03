// RestockDigest.swift
// What Restock needs, read once from the open needs: the office run and the
// to-order list, and the words the page header and Today's card say about
// them. Pure, so the wording is testable without a screen.

import CoreData
import Foundation

/// The open needs, split the way the Restock page and Today's card show them.
nonisolated struct RestockDigest: Equatable, Sendable {

    /// One open need, as the digest names it.
    struct Line: Equatable, Sendable {
        let title: String
        let quantity: Int
        /// The staple's level for a staple's need; nil for a one-off.
        let level: RestockLevel?

        /// "Toilet Paper", "Glue sticks ×12": a one-off's count when it's
        /// more than one (a staple's need is for "some").
        var label: String {
            level == nil && quantity > 1 ? "\(title) ×\(quantity)" : title
        }
    }

    /// Needs from the office: everything to fetch on the next walk there.
    var officeRun: [Line] = []
    /// Needs to order that haven't been asked for yet (one asked for waits on
    /// the office, not on the guide, so it isn't counted as needed).
    var toOrder: [Line] = []

    static let empty = RestockDigest()

    var total: Int { officeRun.count + toOrder.count }
    var isEmpty: Bool { total == 0 }

    /// Builds the digest from open needs (`RestockService.openNeeds`), oldest
    /// first. `levels` gives each staple's level by its upper-cased id, for
    /// the Out or Low a staple's need carries.
    static func make(needs: [CDOrderItem], levels: [String: RestockLevel] = [:]) -> RestockDigest {
        var digest = RestockDigest()
        for need in needs where need.receivedAt == nil && !need.isDeleted {
            let level: RestockLevel? = need.isStapleNeed
                ? levels[(need.supplyID ?? "").uppercased()] ?? .low
                : nil
            let line = Line(title: need.displayTitle, quantity: Int(need.quantity), level: level)
            switch need.source {
            case .office: digest.officeRun.append(line)
            case .order where need.requestedAt == nil: digest.toOrder.append(line)
            case .order: break
            }
        }
        return digest
    }

    /// Each staple's level by its upper-cased id, for `make`.
    static func levels(of staples: [CDSupply]) -> [String: RestockLevel] {
        var levels: [String: RestockLevel] = [:]
        for staple in staples {
            guard let id = staple.id?.uuidString.uppercased() else { continue }
            levels[id] = staple.level
        }
        return levels
    }

    // MARK: - Words

    /// The page's line beside "Needs": "6 things: 3 from the office, 3 to order".
    var headerLine: String {
        guard !isEmpty else { return "Nothing needed" }
        let things = total == 1 ? "1 thing" : "\(total) things"
        return "\(things): \(officeRun.count) from the office, \(toOrder.count) to order"
    }

    /// Today's card: "Restock: 3 for the office run, 3 to order". Nil when
    /// nothing is needed, so the card doesn't show.
    var cardTitle: String? {
        var parts: [String] = []
        if !officeRun.isEmpty { parts.append("\(officeRun.count) for the office run") }
        if !toOrder.isEmpty { parts.append("\(toOrder.count) to order") }
        guard !parts.isEmpty else { return nil }
        return "Restock: " + parts.joined(separator: ", ")
    }

    /// The first few things by name, office run first: "Toilet Paper, Paper
    /// Towels, Glue sticks ×12 and 3 more".
    var cardSubtitle: String {
        let labels = (officeRun + toOrder).map(\.label)
        let shown = labels.prefix(Self.namedOnCard)
        let rest = labels.count - shown.count
        let list = shown.joined(separator: ", ")
        return rest > 0 ? "\(list) and \(rest) more" : list
    }

    /// How many things Today's card names before "and N more".
    static let namedOnCard = 3
}
