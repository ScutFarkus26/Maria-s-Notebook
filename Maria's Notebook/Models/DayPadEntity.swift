import Foundation
import CoreData

@objc(CDDayPad)
public class CDDayPad: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var day: Date?
    @NSManaged public var body: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext, day: Date) {
        let entity = NSEntityDescription.entity(forEntityName: "DayPad", in: context)!
        self.init(entity: entity, insertInto: context)
        let now = Date()
        self.id = UUID()
        self.day = day
        self.body = ""
        self.createdAt = now
        self.modifiedAt = now
    }
}

extension CDDayPad {
    func setBody(_ newValue: String) {
        guard body != newValue else { return }
        body = newValue
        modifiedAt = Date()
    }
}
