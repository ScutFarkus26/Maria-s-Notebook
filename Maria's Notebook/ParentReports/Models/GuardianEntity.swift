// GuardianEntity.swift
// Core Data entity for a student's parent/guardian contact (private store).

import Foundation
import CoreData

@objc(CDGuardian)
public class CDGuardian: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var name: String
    @NSManaged public var email: String
    @NSManaged public var relationshipRaw: String
    @NSManaged public var receivesReports: Bool
    @NSManaged public var sortOrder: Int64
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Computed Properties

    var relationship: GuardianRelationship {
        get { GuardianRelationship(rawValue: relationshipRaw) ?? .parent }
        set { relationshipRaw = newValue.rawValue }
    }

    var studentUUID: UUID? { UUID(uuidString: studentID) }

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Guardian", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.name = ""
        self.email = ""
        self.relationshipRaw = GuardianRelationship.parent.rawValue
        self.receivesReports = true
        self.sortOrder = 0
        self.notes = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    // MARK: - Fetching

    /// Guardians for one student, ordered by sortOrder then name.
    nonisolated static func fetchRequest(studentID: String) -> NSFetchRequest<CDGuardian> {
        let request = NSFetchRequest<CDGuardian>(entityName: "Guardian")
        request.predicate = NSPredicate(format: "studentID == %@", studentID)
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        return request
    }
}

enum GuardianRelationship: String, CaseIterable, Identifiable, Sendable {
    case parent
    case mother
    case father
    case guardian
    case grandparent
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .parent: return "Parent"
        case .mother: return "Mother"
        case .father: return "Father"
        case .guardian: return "Guardian"
        case .grandparent: return "Grandparent"
        case .other: return "Other"
        }
    }
}
