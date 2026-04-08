// WorkCycleEntryEntity.swift
// Core Data entity for an individual student's activity record during a work cycle session.

import Foundation
import CoreData

@objc(CDWorkCycleEntry)
public class CDWorkCycleEntry: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var sessionID: String
    @NSManaged public var studentID: String
    @NSManaged public var activityDescription: String
    @NSManaged public var socialModeRaw: String
    @NSManaged public var concentrationRaw: String
    @NSManaged public var startTime: Date?
    @NSManaged public var endTime: Date?
    @NSManaged public var workItemID: String?
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "WorkCycleEntry", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.sessionID = ""
        self.studentID = ""
        self.activityDescription = ""
        self.socialModeRaw = SocialMode.independent.rawValue
        self.concentrationRaw = ConcentrationLevel.focused.rawValue
        self.startTime = Date()
        self.endTime = nil
        self.workItemID = nil
        self.notes = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Computed Properties

extension CDWorkCycleEntry {
    var socialMode: SocialMode {
        get { SocialMode(rawValue: socialModeRaw) ?? .independent }
        set {
            socialModeRaw = newValue.rawValue
            modifiedAt = Date()
        }
    }

    var concentration: ConcentrationLevel {
        get { ConcentrationLevel(rawValue: concentrationRaw) ?? .focused }
        set {
            concentrationRaw = newValue.rawValue
            modifiedAt = Date()
        }
    }

    var sessionUUID: UUID? { UUID(uuidString: sessionID) }
    var studentUUID: UUID? { UUID(uuidString: studentID) }
    var workItemUUID: UUID? {
        guard let idStr = workItemID else { return nil }
        return UUID(uuidString: idStr)
    }

    /// Duration in seconds, computed from start/end times.
    var duration: TimeInterval {
        guard let start = startTime else { return 0 }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }
}
