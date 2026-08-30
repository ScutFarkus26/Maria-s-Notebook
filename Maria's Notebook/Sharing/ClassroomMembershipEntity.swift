import Foundation
import CoreData

@objc(ClassroomMembership)
public class CDClassroomMembership: NSManagedObject {
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

// MARK: - Enums

extension CDClassroomMembership {
}

// MARK: - Computed Properties

extension CDClassroomMembership {
    var role: ClassroomRole {
        get { ClassroomRole(rawValue: roleRaw) ?? .leadGuide }
        set { roleRaw = newValue.rawValue }
    }

    /// The device's role, read straight from the membership row. A notebook with
    /// no membership yet (solo use, before any share exists) is its own lead guide.
    static func currentRole(in context: NSManagedObjectContext) -> ClassroomRole {
        let request = CDFetchRequest(CDClassroomMembership.self)
        request.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: true)]
        request.fetchLimit = 1
        return context.safeFetchFirst(request)?.role ?? .leadGuide
    }
}
