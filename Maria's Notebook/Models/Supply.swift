import Foundation
import SwiftData

/// Categories for classroom supplies
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

    var id: String { rawValue }

    var icon: String {
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

/// Represents the stock status of a supply
enum SupplyStatus: String, Codable, Sendable {
    case healthy = "Healthy"
    case low = "Low"
    case critical = "Critical"
    case outOfStock = "Out of Stock"

    var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .low: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.circle.fill"
        case .outOfStock: return "xmark.circle.fill"
        }
    }
}

/// A supply item tracked in the classroom inventory
@Model
final class Supply: Identifiable {
    /// Unique identifier
    var id: UUID = UUID()

    /// Name of the supply item
    var name: String = ""

    /// Category stored as raw string for CloudKit compatibility
    private var categoryRaw: String = SupplyCategory.other.rawValue

    /// Storage location in the classroom
    var location: String = ""

    /// Current quantity in stock
    var currentQuantity: Int = 0

    /// Minimum threshold before needing reorder
    var minimumThreshold: Int = 0

    /// Suggested quantity to reorder
    var reorderAmount: Int = 0

    /// Unit of measurement (e.g., "boxes", "packs", "items")
    var unit: String = "items"

    /// Additional notes about this supply
    var notes: String = ""

    /// When this supply was created
    var createdAt: Date = Date()

    /// When this supply was last modified
    var modifiedAt: Date = Date()

    /// Transaction history for this supply
    @Relationship(deleteRule: .cascade, inverse: \SupplyTransaction.supply)
    var transactions: [SupplyTransaction]? = []

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

    init(
        id: UUID = UUID(),
        name: String,
        category: SupplyCategory = .other,
        location: String = "",
        currentQuantity: Int = 0,
        minimumThreshold: Int = 0,
        reorderAmount: Int = 0,
        unit: String = "items",
        notes: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.categoryRaw = category.rawValue
        self.location = location
        self.currentQuantity = currentQuantity
        self.minimumThreshold = minimumThreshold
        self.reorderAmount = reorderAmount
        self.unit = unit
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Adjusts the quantity and records a transaction
    func adjustQuantity(by amount: Int, reason: String, in context: ModelContext) {
        currentQuantity += amount
        modifiedAt = Date()

        let transaction = SupplyTransaction(
            supplyID: id.uuidString,
            quantityChange: amount,
            reason: reason,
            supply: self
        )
        context.insert(transaction)
    }
}

/// A record of a supply quantity change
@Model
final class SupplyTransaction: Identifiable {
    /// Unique identifier
    var id: UUID = UUID()

    /// Reference to the supply (stored as String for CloudKit compatibility)
    var supplyID: String = ""

    /// When this transaction occurred
    var date: Date = Date()

    /// Amount changed (positive = added, negative = removed)
    var quantityChange: Int = 0

    /// Reason for the change
    var reason: String = ""

    /// Reference to the parent supply
    @Relationship var supply: Supply?

    init(
        id: UUID = UUID(),
        supplyID: String,
        date: Date = Date(),
        quantityChange: Int,
        reason: String,
        supply: Supply? = nil
    ) {
        self.id = id
        self.supplyID = supplyID
        self.date = date
        self.quantityChange = quantityChange
        self.reason = reason
        self.supply = supply
    }
}
