import Foundation
import CoreData

/// One person in the classroom and the name they go by, as they typed it.
///
/// Lives in the classroom share (schema 16), so the guide's devices show each
/// assistant's current name and her phone shows the guide's. Screens look the
/// name up by a stamp's record name when they word a line, so a rename reaches
/// old entries too. Each person writes only their own row; two of the guide's
/// devices can each write one before the other's arrives, so reads take the
/// newest. Read and write it through `ClassroomNames`, never directly.
@objc(CDClassroomPerson)
nonisolated public class CDClassroomPerson: NSManagedObject {
    @NSManaged public var id: UUID?
    /// The person's CloudKit user record name in the classroom's container
    /// (`ClassroomIdentity.currentUserRecordName`): whose row this is, and
    /// what a stamp's `…ByID` is matched against.
    @NSManaged public var recordName: String
    /// The person's `CDClassroomMembership.ClassroomRole` raw value.
    @NSManaged public var roleRaw: String
    /// The name as typed. Empty when the person cleared it: the row stays, so
    /// another device's older row can't bring the old name back.
    @NSManaged public var displayName: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ClassroomPerson", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        let now = Date()
        self.createdAt = now
        self.modifiedAt = now
    }
}

nonisolated extension CDClassroomPerson: Identifiable {}

nonisolated extension CDClassroomPerson {
    var role: CDClassroomMembership.ClassroomRole {
        get { CDClassroomMembership.ClassroomRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }
}
