// PrepChecklistCompletionEntity.swift
// Core Data entity for daily checklist item completion records.

import Foundation
import CoreData

@objc(CDPrepChecklistCompletion)
public class CDPrepChecklistCompletion: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var checklistItemID: String
    @NSManaged public var date: Date?
    @NSManaged public var completedAt: Date?
    @NSManaged public var completedBy: String
    @NSManaged public var createdAt: Date?

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "PrepChecklistCompletion", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.checklistItemID = ""
        self.date = Calendar.current.startOfDay(for: Date())
        self.completedAt = Date()
        self.completedBy = ""
        self.createdAt = Date()
    }
}
