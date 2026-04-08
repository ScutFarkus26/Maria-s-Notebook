// ParentCommunicationEntity.swift
// Core Data entity for tracking parent communications (drafts and sent).

import Foundation
import CoreData

@objc(CDParentCommunication)
public class CDParentCommunication: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var templateName: String
    @NSManaged public var subject: String
    @NSManaged public var body: String
    @NSManaged public var communicationTypeRaw: String
    @NSManaged public var sentAt: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var notes: String

    // MARK: - Computed Properties

    var communicationType: CommunicationType {
        get { CommunicationType(rawValue: communicationTypeRaw) ?? .custom }
        set { communicationTypeRaw = newValue.rawValue }
    }

    var isDraft: Bool { sentAt == nil }

    var studentUUID: UUID? { UUID(uuidString: studentID) }

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ParentCommunication", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.templateName = ""
        self.subject = ""
        self.body = ""
        self.communicationTypeRaw = CommunicationType.custom.rawValue
        self.sentAt = nil
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.notes = ""
    }
}
