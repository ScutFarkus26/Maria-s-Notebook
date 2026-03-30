import Foundation
import CoreData

@objc(CalendarEvent)
public class CalendarEvent: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var startDate: Date?
    @NSManaged public var endDate: Date?
    @NSManaged public var location: String?
    @NSManaged public var notes: String?
    @NSManaged public var isAllDay: Bool
    @NSManaged public var eventKitEventID: String?
    @NSManaged public var eventKitCalendarID: String?
    @NSManaged public var lastSyncedAt: Date?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "CalendarEvent", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.startDate = Date()
        self.endDate = Date()
        self.location = nil
        self.notes = nil
        self.isAllDay = false
        self.eventKitEventID = nil
        self.eventKitCalendarID = nil
        self.lastSyncedAt = nil
    }
}
