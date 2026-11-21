// LevelChangeEntity.swift
// Core Data entity for one step in a child's level history (private store,
// schema 25).

import Foundation
import CoreData

/// One change of a child's level: from which, to which, and the day it took
/// effect (plan "Domain logic fixes", Decision 13). The guide's own, keyed to
/// the child by `studentID`; never in the classroom share. A change undone the
/// same day removes the pair, so a mis-tap leaves no history, and a monthly
/// report reads the level she had that month from these rows.
@objc(CDLevelChange)
nonisolated public class CDLevelChange: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    /// `CDStudent.Level` raw values; "" when there was none.
    @NSManaged public var fromLevelRaw: String
    @NSManaged public var toLevelRaw: String
    /// The day the change took effect (a start of day).
    @NSManaged public var changedOn: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "LevelChange", in: context)!
        self.init(entity: entity, insertInto: context)
        let now = Date()
        self.id = UUID()
        self.studentID = ""
        self.fromLevelRaw = ""
        self.toLevelRaw = ""
        self.changedOn = nil
        self.createdAt = now
        self.modifiedAt = now
    }
}

// MARK: - Computed Properties

nonisolated extension CDLevelChange {
    /// The level before the change; nil when the row names none.
    var fromLevel: CDStudent.Level? { CDStudent.Level(rawValue: fromLevelRaw) }
    /// The level after the change; nil for a raw value no build knows.
    var toLevel: CDStudent.Level? { CDStudent.Level(rawValue: toLevelRaw) }
}
