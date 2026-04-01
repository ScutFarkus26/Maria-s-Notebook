import Foundation
import CoreData

@objc(SchoolDayOverride)
public class CDSchoolDayOverride: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var date: Date?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "SchoolDayOverride", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - Cross-Store Inverse

extension CDSchoolDayOverride {
    /// Cross-store inverse: fetches Notes whose schoolDayOverrideID matches this override.
    var notes: [CDNote] {
        guard let id, let ctx = managedObjectContext else { return [] }
        let req = CDFetchRequest(CDNote.self)
        req.predicate = NSPredicate(format: "schoolDayOverrideID == %@", id.uuidString)
        return (try? ctx.fetch(req)) ?? []
    }
}

