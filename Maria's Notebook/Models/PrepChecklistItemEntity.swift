// PrepChecklistItemEntity.swift
// Core Data entity for items within a prep checklist.

import Foundation
import CoreData

@objc(CDPrepChecklistItem)
public class CDPrepChecklistItem: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var checklistID: String
    @NSManaged public var title: String
    @NSManaged public var category: String
    @NSManaged public var sortOrder: Int64
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Relationships
    @NSManaged public var checklist: CDPrepChecklist?

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "PrepChecklistItem", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.checklistID = ""
        self.title = ""
        self.category = ""
        self.sortOrder = 0
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
