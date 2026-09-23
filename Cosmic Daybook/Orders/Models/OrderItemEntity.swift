// OrderItemEntity.swift
// Core Data entity for one thing the guide wants the office to order (private store).

import Foundation
import CoreData

/// One link the guide dropped into Orders, followed from "to request" through
/// "received".
///
/// The stage is not stored. It is read off the three dates — received beats
/// confirmed beats asked for — so there is no status column that could
/// disagree with them, and each date merges on its own when two devices edit
/// the same item. Every change goes through `OrderService`.
@objc(CDOrderItem)
nonisolated public class CDOrderItem: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var urlString: String
    @NSManaged public var title: String
    @NSManaged public var quantity: Int64
    @NSManaged public var notes: String
    /// Shared by every item asked for in the same message, so the office's
    /// confirmation can be marked against the request as a whole.
    @NSManaged public var requestID: String?
    /// Who was asked, as the request settings named them at the time.
    @NSManaged public var requestedFrom: String
    @NSManaged public var requestedAt: Date?
    @NSManaged public var confirmedAt: Date?
    @NSManaged public var receivedAt: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Computed Properties

    var stage: OrderStage {
        if receivedAt != nil { return .received }
        if confirmedAt != nil { return .confirmed }
        if requestedAt != nil { return .requested }
        return .toRequest
    }

    var url: URL? {
        let trimmed = urlString.trimmed()
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    /// The site the link points at, without a leading "www.".
    var host: String? {
        guard let host = url?.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// What the row prints under the title: the site, or — while there is no
    /// title and the site is already standing in for it — the link itself.
    var linkCaption: String? {
        guard !title.trimmed().isEmpty else {
            let link = urlString.trimmed()
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "www.", with: "")
            return link.isEmpty || link == host ? nil : link
        }
        return host
    }

    /// The title, or the site's name while the title is still being fetched.
    var displayTitle: String {
        let trimmed = title.trimmed()
        if !trimmed.isEmpty { return trimmed }
        return host ?? (urlString.isEmpty ? "Untitled item" : urlString)
    }

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "OrderItem", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.urlString = ""
        self.title = ""
        self.quantity = 1
        self.notes = ""
        self.requestID = nil
        self.requestedFrom = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

/// Where an order stands. Derived from `CDOrderItem`'s dates, never stored.
enum OrderStage: String, CaseIterable, Identifiable, Sendable {
    case toRequest
    case requested
    case confirmed
    case received

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .toRequest: return "To Request"
        case .requested: return "Asked For"
        case .confirmed: return "Confirmed"
        case .received: return "Received"
        }
    }

    var icon: String {
        switch self {
        case .toRequest: return "cart"
        case .requested: return "paperplane"
        case .confirmed: return "checkmark.seal"
        case .received: return "shippingbox"
        }
    }
}
