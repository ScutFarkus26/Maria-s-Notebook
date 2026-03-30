import Foundation
import CoreData

@objc(GoingOut)
public class GoingOut: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var title: String
    @NSManaged public var purpose: String
    @NSManaged public var destination: String
    @NSManaged public var proposedDate: Date?
    @NSManaged public var actualDate: Date?
    @NSManaged public var statusRaw: String
    @NSManaged public var studentIDs: NSObject?  // Transformable [String]
    @NSManaged public var curriculumLinkIDs: String
    @NSManaged public var permissionStatusRaw: String
    @NSManaged public var notes: String
    @NSManaged public var followUpWork: String
    @NSManaged public var supervisorName: String

    // MARK: - Relationships
    @NSManaged public var checklistItems: NSSet?
    @NSManaged public var observationNotes: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "GoingOut", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.title = ""
        self.purpose = ""
        self.destination = ""
        self.proposedDate = nil
        self.actualDate = nil
        self.statusRaw = GoingOutStatus.proposed.rawValue
        self.studentIDs = [] as NSArray
        self.curriculumLinkIDs = ""
        self.permissionStatusRaw = PermissionStatus.pending.rawValue
        self.notes = ""
        self.followUpWork = ""
        self.supervisorName = ""
    }
}

// MARK: - Enums

extension GoingOut {
    enum GoingOutStatus: String, CaseIterable, Identifiable, Codable, Sendable {
        case proposed
        case planning
        case approved
        case completed
        case cancelled

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .proposed: return "Proposed"
            case .planning: return "Planning"
            case .approved: return "Approved"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            }
        }

        public var icon: String {
            switch self {
            case .proposed: return "lightbulb"
            case .planning: return "list.clipboard"
            case .approved: return "checkmark.seal"
            case .completed: return "flag.checkered"
            case .cancelled: return "xmark.circle"
            }
        }
    }

    enum PermissionStatus: String, CaseIterable, Identifiable, Codable, Sendable {
        case pending
        case sent
        case approved
        case denied

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .sent: return "Sent"
            case .approved: return "Approved"
            case .denied: return "Denied"
            }
        }

        public var icon: String {
            switch self {
            case .pending: return "clock"
            case .sent: return "envelope"
            case .approved: return "checkmark.circle"
            case .denied: return "xmark.circle"
            }
        }
    }
}

// MARK: - Computed Properties

extension GoingOut {
    var status: GoingOutStatus {
        get { GoingOutStatus(rawValue: statusRaw) ?? .proposed }
        set { statusRaw = newValue.rawValue; modifiedAt = Date() }
    }

    var permissionStatus: PermissionStatus {
        get { PermissionStatus(rawValue: permissionStatusRaw) ?? .pending }
        set { permissionStatusRaw = newValue.rawValue; modifiedAt = Date() }
    }

    /// Access studentIDs as a Swift [String] array
    var studentIDsArray: [String] {
        get { (studentIDs as? [String]) ?? [] }
        set { studentIDs = newValue as NSArray }
    }

    var studentUUIDs: [UUID] {
        get { studentIDsArray.compactMap { UUID(uuidString: $0) } }
        set { studentIDsArray = newValue.map(\.uuidString) }
    }

    var curriculumLinkUUIDs: [UUID] {
        get {
            curriculumLinkIDs
                .components(separatedBy: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
        set {
            curriculumLinkIDs = newValue.map(\.uuidString).joined(separator: ",")
        }
    }

    var sortedChecklistItems: [GoingOutChecklistItem] {
        ((checklistItems as? Set<GoingOutChecklistItem>).map(Array.init) ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension GoingOut {
    @objc(addChecklistItemsObject:)
    @NSManaged public func addToChecklistItems(_ value: GoingOutChecklistItem)

    @objc(removeChecklistItemsObject:)
    @NSManaged public func removeFromChecklistItems(_ value: GoingOutChecklistItem)

    @objc(addChecklistItems:)
    @NSManaged public func addToChecklistItems(_ values: NSSet)

    @objc(removeChecklistItems:)
    @NSManaged public func removeFromChecklistItems(_ values: NSSet)

    @objc(addObservationNotesObject:)
    @NSManaged public func addToObservationNotes(_ value: Note)

    @objc(removeObservationNotesObject:)
    @NSManaged public func removeFromObservationNotes(_ value: Note)

    @objc(addObservationNotes:)
    @NSManaged public func addToObservationNotes(_ values: NSSet)

    @objc(removeObservationNotes:)
    @NSManaged public func removeFromObservationNotes(_ values: NSSet)
}
