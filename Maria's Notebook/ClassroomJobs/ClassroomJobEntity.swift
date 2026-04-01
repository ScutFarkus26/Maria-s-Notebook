import Foundation
import CoreData
import SwiftUI

@objc(CDClassroomJob)
public class CDClassroomJob: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var name: String
    @NSManaged public var jobDescription: String
    @NSManaged public var icon: String
    @NSManaged public var colorRaw: String
    @NSManaged public var sortOrder: Int64
    @NSManaged public var isActive: Bool
    @NSManaged public var maxStudents: Int64

    // MARK: - Relationships
    @NSManaged public var assignments: NSSet?

    // MARK: - Computed Properties
    var color: Color {
        switch colorRaw {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        default: return .gray
        }
    }

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ClassroomJob", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.name = ""
        self.jobDescription = ""
        self.icon = "star"
        self.colorRaw = "blue"
        self.sortOrder = 0
        self.isActive = true
        self.maxStudents = 1
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDClassroomJob {
    @objc(addAssignmentsObject:)
    @NSManaged public func addToAssignments(_ value: CDJobAssignment)

    @objc(removeAssignmentsObject:)
    @NSManaged public func removeFromAssignments(_ value: CDJobAssignment)

    @objc(addAssignments:)
    @NSManaged public func addToAssignments(_ values: NSSet)

    @objc(removeAssignments:)
    @NSManaged public func removeFromAssignments(_ values: NSSet)
}
