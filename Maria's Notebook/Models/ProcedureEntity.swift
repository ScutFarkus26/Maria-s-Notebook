import Foundation
import CoreData

@objc(Procedure)
public class CDProcedure: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var summary: String
    @NSManaged public var content: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var icon: String
    @NSManaged public var relatedProcedureIDsRaw: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Procedure", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.summary = ""
        self.content = ""
        self.categoryRaw = ProcedureCategory.other.rawValue
        self.icon = ""
        self.relatedProcedureIDsRaw = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Enums

extension CDProcedure {
}

// MARK: - Computed Properties

extension CDProcedure {
    /// Computed property for category enum
    var category: ProcedureCategory {
        get { ProcedureCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Computed property for related procedure IDs
    var relatedProcedureIDs: [String] {
        get {
            guard !relatedProcedureIDsRaw.isEmpty else { return [] }
            return relatedProcedureIDsRaw.components(separatedBy: ",")
        }
        set {
            relatedProcedureIDsRaw = newValue.joined(separator: ",")
        }
    }

    /// Display icon - uses custom icon if set, otherwise category default
    var displayIcon: String {
        icon.isEmpty ? category.icon : icon
    }

    /// Updates the modification timestamp
    func touch() {
        modifiedAt = Date()
    }
}
