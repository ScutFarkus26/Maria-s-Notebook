import CoreData
import Foundation

/// A deleted row's values, kept so an Undo can put it back.
///
/// Holds every attribute, and the rows its cascading to-many relationships
/// would take with it (a presentation's notes, and each note's student links),
/// so the recreated object comes back with what the delete removed. Other
/// relationships aren't kept: a row reached only through a cascade belongs to
/// its parent. The recreated object is a new row carrying the same values,
/// including its `id`.
struct ManagedObjectSnapshot {
    let entityName: String
    let attributes: [String: Any]
    let children: [String: [ManagedObjectSnapshot]]

    init?(_ object: NSManagedObject) {
        guard let entityName = object.entity.name else { return nil }
        self.entityName = entityName
        attributes = object.dictionaryWithValues(forKeys: Array(object.entity.attributesByName.keys))
        var children: [String: [ManagedObjectSnapshot]] = [:]
        for (name, relationship) in object.entity.relationshipsByName
            where relationship.isToMany && relationship.deleteRule == .cascadeDeleteRule {
            let related = (object.value(forKey: name) as? Set<NSManagedObject>) ?? []
            children[name] = related.filter { !$0.isDeleted }.compactMap(ManagedObjectSnapshot.init)
        }
        self.children = children
    }

    /// Inserts a new object with these values into `context`. Does not save.
    @discardableResult
    func recreate(in context: NSManagedObjectContext) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
        for (key, value) in attributes {
            object.setValue(value is NSNull ? nil : value, forKey: key)
        }
        for (name, snapshots) in children where !snapshots.isEmpty {
            let related = object.mutableSetValue(forKey: name)
            for child in snapshots {
                related.add(child.recreate(in: context))
            }
        }
        return object
    }
}
