import Foundation
import CoreData

@objc(ClassroomMembership)
public class ClassroomMembership: NSManagedObject {
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

extension ClassroomMembership {
    enum ClassroomRole: String, Codable, CaseIterable, Sendable {
        case leadGuide
        case assistant
    }
}

// MARK: - Computed Properties

extension ClassroomMembership {
    var role: ClassroomRole {
        get { ClassroomRole(rawValue: roleRaw) ?? .leadGuide }
        set { roleRaw = newValue.rawValue }
    }
}
