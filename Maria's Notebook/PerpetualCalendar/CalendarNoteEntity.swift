import Foundation
import CoreData

@objc(CalendarNote)
public class CDCalendarNote: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var year: Int64
    @NSManaged public var month: Int64
    @NSManaged public var day: Int64
    @NSManaged public var text: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "CalendarNote", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.year = 2026
        self.month = 1
        self.day = 1
        self.text = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
