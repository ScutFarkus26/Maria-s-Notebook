import Foundation
import CoreData

/// Describes how work is assigned in a project session

@objc(ProjectSession)
public class CDProjectSession: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var projectID: String
    @NSManaged public var meetingDate: Date?
    @NSManaged public var chapterOrPages: String?
    @NSManaged public var agendaItemsJSON: String
    @NSManaged public var templateWeekID: String?
    @NSManaged public var assignmentModeRaw: String
    @NSManaged public var minSelections: Int64
    @NSManaged public var maxSelections: Int64

    // MARK: - Relationships
    @NSManaged public var project: CDProject?
    @NSManaged public var noteItems: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ProjectSession", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.projectID = ""
        self.meetingDate = Date()
        self.chapterOrPages = nil
        self.agendaItemsJSON = ""
        self.templateWeekID = nil
        self.assignmentModeRaw = SessionAssignmentMode.uniform.rawValue
        self.minSelections = 0
        self.maxSelections = 0
    }
}

// MARK: - Computed Properties

extension CDProjectSession {
    var projectIDUUID: UUID? {
        get { UUID(uuidString: projectID) }
        set { projectID = newValue?.uuidString ?? "" }
    }

    var templateWeekIDUUID: UUID? {
        get { templateWeekID.flatMap { UUID(uuidString: $0) } }
        set { templateWeekID = newValue?.uuidString }
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
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDProjectSession {
    @objc(addNoteItemsObject:)
    @NSManaged public func addToNoteItems(_ value: CDNote)

    @objc(removeNoteItemsObject:)
    @NSManaged public func removeFromNoteItems(_ value: CDNote)

    @objc(addNoteItems:)
    @NSManaged public func addToNoteItems(_ values: NSSet)

    @objc(removeNoteItems:)
    @NSManaged public func removeFromNoteItems(_ values: NSSet)
}
