import Foundation
import CoreData

@objc(NonSchoolDay)
nonisolated public class CDNonSchoolDay: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var date: Date?
    @NSManaged public var reason: String?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "NonSchoolDay", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.date = AppCalendar.shared.startOfDay(for: Date())
        self.reason = nil
    }
}
