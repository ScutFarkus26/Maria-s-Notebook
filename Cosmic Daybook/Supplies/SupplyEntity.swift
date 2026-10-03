import Foundation
import CoreData

/// A staple on the Restock shelf: something the classroom always needs.
///
/// In the classroom share since schema 15, so assistants see and mark it. Its
/// level (Stocked, Low, Out) is what counts; Low or Out gives it one open need
/// (`CDOrderItem.supplyID`). `location` is shown as its place. `categoryRaw`
/// stays for old data and backups, out of the UI. Every change goes through
/// `RestockService`.
@objc(CDSupply)
nonisolated public class CDSupply: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var location: String
    @NSManaged public var currentQuantity: Int64
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    /// Low at this count, for counted staples (not used yet).
    @NSManaged public var minimumThreshold: Int64
    /// What a count counts ("items", "boxes"), for counted staples (not used yet).
    @NSManaged public var unit: String
    /// A `RestockLevel` raw value.
    @NSManaged public var levelRaw: String
    /// A `RestockSource` raw value: where its need is filled from.
    @NSManaged public var sourceRaw: String
    /// The product link, for a staple that is ordered.
    @NSManaged public var urlString: String
    /// When the level was last set, and by whom: the CloudKit record name, and
    /// an assistant's name (the guide's changes carry none).
    @NSManaged public var levelChangedAt: Date?
    @NSManaged public var levelChangedByID: String?
    @NSManaged public var levelChangedByName: String

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Supply", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.name = ""
        self.categoryRaw = SupplyCategory.other.rawValue
        self.location = ""
        self.currentQuantity = 0
        self.notes = ""
        self.levelRaw = RestockLevel.stocked.rawValue
        self.sourceRaw = RestockSource.office.rawValue
        self.urlString = ""
        self.levelChangedByName = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Computed Properties

nonisolated extension CDSupply {
    /// Computed property for category enum
    var category: SupplyCategory {
        get { SupplyCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var level: RestockLevel {
        get { RestockLevel(rawValue: levelRaw) ?? .stocked }
        set { levelRaw = newValue.rawValue }
    }

    var source: RestockSource {
        get { RestockSource(rawValue: sourceRaw) ?? .office }
        set { sourceRaw = newValue.rawValue }
    }
}
