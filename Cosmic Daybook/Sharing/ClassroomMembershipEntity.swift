import Foundation
import CoreData

@objc(ClassroomMembership)
nonisolated public class CDClassroomMembership: NSManagedObject {
    // MARK: - Enums
    enum ClassroomRole: String, Codable, CaseIterable, Sendable {
        case leadGuide
        case assistant
    }

    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var classroomZoneID: String
    @NSManaged public var roleRaw: String
    @NSManaged public var ownerIdentity: String
    @NSManaged public var joinedAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ClassroomMembership", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.classroomZoneID = ""
        self.roleRaw = ClassroomRole.leadGuide.rawValue
        self.ownerIdentity = ""
        self.joinedAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Computed Properties

nonisolated extension CDClassroomMembership {
    var role: ClassroomRole {
        get { ClassroomRole(rawValue: roleRaw) ?? .leadGuide }
        set { roleRaw = newValue.rawValue }
    }

    /// The device's role, read straight from the membership row. A notebook with
    /// no membership yet (solo use, before any share exists) is its own lead guide.
    static func currentRole(in context: NSManagedObjectContext) -> ClassroomRole {
        let request = ownRowsRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: true)]
        request.fetchLimit = 1
        return context.safeFetchFirst(request)?.role ?? .leadGuide
    }

    /// The membership rows this app may read as "who I am".
    ///
    /// Membership rows live in the private store, so they sync to every app and
    /// device on the same Apple Account. The companion app would therefore also
    /// see the rows the full notebook writes for that account — a lead guide's
    /// row, if the assistant keeps a notebook of their own — and would then file
    /// attendance as a lead guide, where the guide never sees it. The companion
    /// only ever joins as an assistant, so it reads assistant rows alone.
    static func ownRowsRequest() -> NSFetchRequest<CDClassroomMembership> {
        let request = CDFetchRequest(CDClassroomMembership.self)
        #if ASSISTANT_APP
        request.predicate = NSPredicate(format: "roleRaw == %@", ClassroomRole.assistant.rawValue)
        #endif
        return request
    }
}
