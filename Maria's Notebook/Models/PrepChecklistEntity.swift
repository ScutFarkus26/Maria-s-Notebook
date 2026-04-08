// PrepChecklistEntity.swift
// Core Data entity for classroom environment prep checklists.

import SwiftUI
import CoreData

@objc(CDPrepChecklist)
public class CDPrepChecklist: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var icon: String
    @NSManaged public var colorHex: String
    @NSManaged public var scheduleTypeRaw: String
    @NSManaged public var weekdayMask: Int64
    @NSManaged public var notes: String
    @NSManaged public var sortOrder: Int64
    @NSManaged public var isActive: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Relationships
    @NSManaged public var items: NSSet?

    // MARK: - Computed Properties

    var scheduleType: PrepScheduleType {
        get { PrepScheduleType(rawValue: scheduleTypeRaw) ?? .daily }
        set { scheduleTypeRaw = newValue.rawValue }
    }

    var itemsArray: [CDPrepChecklistItem] {
        let set = items as? Set<CDPrepChecklistItem> ?? []
        return set.sorted { $0.sortOrder < $1.sortOrder }
    }

    var color: Color {
        Color(hex: colorHex) ?? .accentColor
    }

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "PrepChecklist", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.name = ""
        self.icon = "checklist.checked"
        self.colorHex = "#007AFF"
        self.scheduleTypeRaw = PrepScheduleType.daily.rawValue
        self.weekdayMask = 0
        self.notes = ""
        self.sortOrder = 0
        self.isActive = true
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
