import Foundation
import CoreData

@objc(Supply)
public class Supply: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var location: String
    @NSManaged public var currentQuantity: Int64
    @NSManaged public var minimumThreshold: Int64
    @NSManaged public var reorderAmount: Int64
    @NSManaged public var unit: String
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var isOnOrder: Bool
    @NSManaged public var orderedQuantity: Int64
    @NSManaged public var orderDate: Date?

    // MARK: - Relationships
    @NSManaged public var transactions: NSSet?

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
        self.minimumThreshold = 0
        self.reorderAmount = 0
        self.unit = "items"
        self.notes = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isOnOrder = false
        self.orderedQuantity = 0
        self.orderDate = nil
    }
}

// MARK: - Enums

extension Supply {
    enum SupplyCategory: String, Codable, CaseIterable, Identifiable, Sendable {
        case art = "Art"
        case math = "Math"
        case language = "Language"
        case science = "Science"
        case practicalLife = "Practical Life"
        case sensorial = "Sensorial"
        case geography = "Geography"
        case music = "Music"
        case office = "Office"
        case cleaning = "Cleaning"
        case firstAid = "First Aid"
        case other = "Other"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .art: return "paintbrush"
            case .math: return "number"
            case .language: return "textformat"
            case .science: return "flask"
            case .practicalLife: return "hands.sparkles"
            case .sensorial: return "hand.point.up"
            case .geography: return "globe.americas"
            case .music: return "music.note"
            case .office: return "paperclip"
            case .cleaning: return "sparkles"
            case .firstAid: return "cross.case"
            case .other: return "shippingbox"
            }
        }
    }

    enum SupplyStatus: String, Codable, Sendable {
        case healthy = "Healthy"
        case low = "Low"
        case critical = "Critical"
        case outOfStock = "Out of Stock"

        public var icon: String {
            switch self {
            case .healthy: return "checkmark.circle.fill"
            case .low: return "exclamationmark.triangle.fill"
            case .critical: return "exclamationmark.circle.fill"
            case .outOfStock: return "xmark.circle.fill"
            }
        }
    }
}

// MARK: - Computed Properties

extension Supply {
    /// Computed property for category enum
    var category: SupplyCategory {
        get { SupplyCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Computed status based on current quantity vs threshold
    var status: SupplyStatus {
        if currentQuantity <= 0 {
            return .outOfStock
        } else if currentQuantity <= minimumThreshold / 2 {
            return .critical
        } else if currentQuantity <= minimumThreshold {
            return .low
        } else {
            return .healthy
        }
    }

    /// Whether this supply needs to be reordered
    var needsReorder: Bool {
        currentQuantity <= minimumThreshold
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension Supply {
    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: SupplyTransaction)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: SupplyTransaction)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)
}
