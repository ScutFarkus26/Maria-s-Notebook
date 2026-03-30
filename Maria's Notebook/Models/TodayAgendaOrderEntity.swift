import Foundation
import CoreData

@objc(TodayAgendaOrder)
public class CDTodayAgendaOrder: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var day: Date?
    @NSManaged public var itemTypeRaw: String
    @NSManaged public var itemID: UUID?
    @NSManaged public var position: Int64

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "TodayAgendaOrder", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.day = Date.distantPast
        self.itemTypeRaw = ""
        self.itemID = UUID()
        self.position = 0
    }
}

// MARK: - Computed Properties

extension CDTodayAgendaOrder {
    var itemType: AgendaItemType {
        get { AgendaItemType(rawValue: itemTypeRaw) ?? .lesson }
        set { itemTypeRaw = newValue.rawValue }
    }
}
