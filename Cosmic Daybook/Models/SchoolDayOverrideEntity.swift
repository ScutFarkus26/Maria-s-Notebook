import Foundation
import CoreData

@objc(SchoolDayOverride)
nonisolated public class CDSchoolDayOverride: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var date: Date?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "SchoolDayOverride", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.date = AppCalendar.shared.startOfDay(for: Date())
    }
}
