// OrderService.swift
// Every change to an order item: adding links, and moving items through
// asked for → confirmed → received. Callers save; the screen goes through
// SaveCoordinator and the MCP tools through safeSave.

import Foundation
import CoreData

enum OrderService {

    /// How many of one thing a request can ask for.
    static let quantityRange = 1...999

    static func clampedQuantity(_ quantity: Int) -> Int64 {
        Int64(min(max(quantity, quantityRange.lowerBound), quantityRange.upperBound))
    }

    // MARK: - Adding

    /// Turns what the guide typed or pasted into a web link, adding `https://`
    /// when the scheme is missing. Nil for anything that isn't a web address.
    static func webURL(from text: String) -> URL? {
        let trimmed = text.trimmed()
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate), isWebURL(url) else { return nil }
        return url
    }

    /// Only http(s) links with a host — a file dragged in from Finder is not an order.
    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return !(url.host() ?? "").isEmpty
    }

    /// Adds one item per new web link. A link already waiting in the list (not yet
    /// received) is not added twice — dropping the same page again is almost always
    /// a slip, and the quantity field is where "two of these" belongs.
    /// - Returns: the items created, in the order given.
    @discardableResult
    static func addLinks(
        _ urls: [URL],
        title: String? = nil,
        quantity: Int = 1,
        notes: String = "",
        in context: NSManagedObjectContext
    ) -> [CDOrderItem] {
        var waiting = Set(openItems(in: context).map { normalized($0.urlString) })
        var created: [CDOrderItem] = []
        for url in urls where isWebURL(url) {
            let key = normalized(url.absoluteString)
            guard !waiting.contains(key) else { continue }
            waiting.insert(key)
            let item = CDOrderItem(context: context)
            item.urlString = url.absoluteString
            item.title = title?.trimmed() ?? ""
            item.quantity = clampedQuantity(quantity)
            item.notes = notes.trimmed()
            created.append(item)
        }
        return created
    }

    /// Every item not yet received.
    static func openItems(in context: NSManagedObjectContext) -> [CDOrderItem] {
        let request = CDFetchRequest(CDOrderItem.self)
        request.predicate = NSPredicate(format: "receivedAt == nil")
        return context.safeFetch(request)
    }

    /// Case- and trailing-slash-insensitive form of a link, for duplicate checks.
    static func normalized(_ link: String) -> String {
        var value = link.trimmed().lowercased()
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    // MARK: - Moving Through the Stages

    /// Marks items as asked for in one request. They share a request id so the
    /// office's confirmation can later be marked against the whole message.
    static func markRequested(
        _ items: [CDOrderItem],
        from recipient: String,
        at date: Date = Date()
    ) {
        let requestID = UUID().uuidString
        for item in items {
            item.requestID = requestID
            item.requestedFrom = recipient.trimmed()
            item.requestedAt = date
            item.confirmedAt = nil
            item.modifiedAt = date
        }
    }

    /// The office has acknowledged the request.
    static func markConfirmed(_ items: [CDOrderItem], at date: Date = Date()) {
        for item in items where item.confirmedAt == nil {
            item.confirmedAt = date
            item.modifiedAt = date
        }
    }

    /// Takes back a confirmation marked by mistake; the item is asked for again.
    static func clearConfirmation(_ items: [CDOrderItem], at date: Date = Date()) {
        for item in items {
            item.confirmedAt = nil
            item.modifiedAt = date
        }
    }

    /// Checks an item off as arrived, or unchecks it back to where it was.
    static func setReceived(_ items: [CDOrderItem], _ received: Bool, at date: Date = Date()) {
        for item in items where (item.receivedAt != nil) != received {
            item.receivedAt = received ? date : nil
            item.modifiedAt = date
        }
    }

    /// Puts items back on the to-request list, forgetting that they were asked for.
    static func moveBackToRequest(_ items: [CDOrderItem], at date: Date = Date()) {
        for item in items {
            item.requestID = nil
            item.requestedFrom = ""
            item.requestedAt = nil
            item.confirmedAt = nil
            item.receivedAt = nil
            item.modifiedAt = date
        }
    }

    // MARK: - Editing

    static func update(
        _ item: CDOrderItem,
        title: String,
        urlString: String,
        quantity: Int,
        notes: String,
        at date: Date = Date()
    ) {
        item.title = title.trimmed()
        item.urlString = webURL(from: urlString)?.absoluteString ?? urlString.trimmed()
        item.notes = notes.trimmed()
        item.modifiedAt = date
        setQuantity(item, to: quantity, at: date)
    }

    /// How many to ask for, kept within 1...999.
    static func setQuantity(_ item: CDOrderItem, to quantity: Int, at date: Date = Date()) {
        let clamped = clampedQuantity(quantity)
        guard item.quantity != clamped else { return }
        item.quantity = clamped
        item.modifiedAt = date
    }

    static func delete(_ items: [CDOrderItem], in context: NSManagedObjectContext) {
        for item in items {
            context.delete(item)
        }
    }

    // MARK: - Grouping

    /// Items asked for but not yet confirmed or received, one group per request,
    /// oldest first — the request that has waited longest is the one to chase.
    static func openRequests(_ items: [CDOrderItem]) -> [OrderRequestGroup] {
        let waiting = items.filter { $0.stage == .requested }
        let grouped = Dictionary(grouping: waiting) { item in
            // Items asked for outside a drafted message (the MCP tool, older data)
            // group by the day they were asked for.
            item.requestID ?? "day:" + DateFormatters.isoDayPOSIX.string(from: item.requestedAt ?? .distantPast)
        }
        return grouped.map { key, members in
            let sorted = members.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            return OrderRequestGroup(
                id: key,
                requestedAt: sorted.compactMap(\.requestedAt).min(),
                requestedFrom: sorted.first { !$0.requestedFrom.isEmpty }?.requestedFrom ?? "",
                items: sorted
            )
        }
        .sorted { ($0.requestedAt ?? .distantPast) < ($1.requestedAt ?? .distantPast) }
    }
}

/// The items one request asked for, drawn as one block in the Asked For list.
struct OrderRequestGroup: Identifiable {
    let id: String
    let requestedAt: Date?
    let requestedFrom: String
    let items: [CDOrderItem]
}
