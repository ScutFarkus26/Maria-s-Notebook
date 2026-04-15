import Foundation
import CoreData

// MARK: - Focus Item Status

enum FocusItemStatus: String, Codable, CaseIterable, Sendable {
    case active
    case resolved
    case dropped
}

// MARK: - CDStudentFocusItem

@objc(CDStudentFocusItem)
public class CDStudentFocusItem: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var text: String
    @NSManaged public var statusRaw: String
    @NSManaged public var createdInMeetingID: String
    @NSManaged public var resolvedInMeetingID: String?
    @NSManaged public var resolvedAt: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var sortOrder: Int64

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "StudentFocusItem", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.text = ""
        self.statusRaw = FocusItemStatus.active.rawValue
        self.createdInMeetingID = ""
        self.resolvedInMeetingID = nil
        self.resolvedAt = nil
        self.createdAt = Date()
        self.sortOrder = 0
    }
}

// MARK: - Computed Properties

extension CDStudentFocusItem {
    var status: FocusItemStatus {
        get { FocusItemStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }

    var createdInMeetingIDUUID: UUID? {
        get { UUID(uuidString: createdInMeetingID) }
        set { createdInMeetingID = newValue?.uuidString ?? "" }
    }

    var resolvedInMeetingIDUUID: UUID? {
        get {
            guard let resolved = resolvedInMeetingID else { return nil }
            return UUID(uuidString: resolved)
        }
        set { resolvedInMeetingID = newValue?.uuidString }
    }

    var isActive: Bool { status == .active }
    var isResolved: Bool { status == .resolved }
    var isDropped: Bool { status == .dropped }
}
