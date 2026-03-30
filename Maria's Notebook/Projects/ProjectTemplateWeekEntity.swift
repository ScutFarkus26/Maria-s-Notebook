import Foundation
import CoreData

/// Represents a work offer in a template (stored as JSON)
public struct TemplateOfferedWork: Codable, Identifiable, Equatable, Sendable {
    public var id: String = UUID().uuidString
    public var title: String = ""
    public var instructions: String = ""
}

@objc(ProjectTemplateWeek)
public class ProjectTemplateWeek: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var projectID: String
    @NSManaged public var weekIndex: Int64
    @NSManaged public var readingRange: String
    @NSManaged public var agendaItemsJSON: String
    @NSManaged public var linkedLessonIDsJSON: String
    @NSManaged public var workInstructions: String
    @NSManaged public var assignmentModeRaw: String
    @NSManaged public var minSelections: Int64
    @NSManaged public var maxSelections: Int64
    @NSManaged public var offeredWorksJSON: String

    // MARK: - Relationships
    @NSManaged public var roleAssignments: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ProjectTemplateWeek", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.projectID = ""
        self.weekIndex = 0
        self.readingRange = ""
        self.agendaItemsJSON = ""
        self.linkedLessonIDsJSON = ""
        self.workInstructions = ""
        self.assignmentModeRaw = SessionAssignmentMode.uniform.rawValue
        self.minSelections = 0
        self.maxSelections = 0
        self.offeredWorksJSON = ""
    }
}

// MARK: - Computed Properties

extension ProjectTemplateWeek {
    var projectIDUUID: UUID? {
        get { UUID(uuidString: projectID) }
        set { projectID = newValue?.uuidString ?? "" }
    }

    /// Type-safe access to assignment mode
    var assignmentMode: SessionAssignmentMode {
        get { SessionAssignmentMode(rawValue: assignmentModeRaw) ?? .uniform }
        set { assignmentModeRaw = newValue.rawValue }
    }

    /// Decode agenda items from JSON string
    var agendaItems: [String] {
        get {
            let trimmed = agendaItemsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            guard !newValue.isEmpty else { agendaItemsJSON = ""; return }
            if let data = try? JSONEncoder().encode(newValue),
               let s = String(data: data, encoding: .utf8) {
                agendaItemsJSON = s
            } else {
                agendaItemsJSON = ""
            }
        }
    }

    /// Decode linked lesson IDs from JSON string
    var linkedLessonIDs: [String] {
        get {
            let trimmed = linkedLessonIDsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            guard !newValue.isEmpty else { linkedLessonIDsJSON = ""; return }
            if let data = try? JSONEncoder().encode(newValue),
               let s = String(data: data, encoding: .utf8) {
                linkedLessonIDsJSON = s
            } else {
                linkedLessonIDsJSON = ""
            }
        }
    }

    /// Type-safe access to offered works
    var offeredWorks: [TemplateOfferedWork] {
        get {
            let trimmed = offeredWorksJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([TemplateOfferedWork].self, from: data)) ?? []
        }
        set {
            guard !newValue.isEmpty else { offeredWorksJSON = ""; return }
            if let data = try? JSONEncoder().encode(newValue),
               let s = String(data: data, encoding: .utf8) {
                offeredWorksJSON = s
            } else {
                offeredWorksJSON = ""
            }
        }
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension ProjectTemplateWeek {
    @objc(addRoleAssignmentsObject:)
    @NSManaged public func addToRoleAssignments(_ value: ProjectWeekRoleAssignment)

    @objc(removeRoleAssignmentsObject:)
    @NSManaged public func removeFromRoleAssignments(_ value: ProjectWeekRoleAssignment)

    @objc(addRoleAssignments:)
    @NSManaged public func addToRoleAssignments(_ values: NSSet)

    @objc(removeRoleAssignments:)
    @NSManaged public func removeFromRoleAssignments(_ values: NSSet)
}
