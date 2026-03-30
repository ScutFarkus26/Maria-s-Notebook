import Foundation
import CoreData

@objc(SchoolDayOverride)
public class SchoolDayOverride: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var date: Date?

    // MARK: - Relationships
    @NSManaged public var notes: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "SchoolDayOverride", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension SchoolDayOverride {
    @objc(addNotesObject:)
    @NSManaged public func addToNotes(_ value: Note)

    @objc(removeNotesObject:)
    @NSManaged public func removeFromNotes(_ value: Note)

    @objc(addNotes:)
    @NSManaged public func addToNotes(_ values: NSSet)

    @objc(removeNotes:)
    @NSManaged public func removeFromNotes(_ values: NSSet)
}
