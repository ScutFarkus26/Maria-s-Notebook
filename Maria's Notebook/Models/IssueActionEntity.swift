import Foundation
import CoreData

@objc(IssueAction)
public class IssueAction: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var issueID: String
    @NSManaged public var actionTypeRaw: String
    @NSManaged public var actionDescription: String
    @NSManaged public var actionDate: Date?
    @NSManaged public var _participantIDsData: Data?
    @NSManaged public var nextSteps: String?
    @NSManaged public var followUpRequired: Bool
    @NSManaged public var followUpDate: Date?
    @NSManaged public var followUpCompleted: Bool

    // MARK: - Relationships
    @NSManaged public var issue: Issue?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "IssueAction", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modifiedAt = Date()
        self.issueID = ""
        self.actionTypeRaw = IssueActionType.note.rawValue
        self.actionDescription = ""
        self.actionDate = Date()
        self._participantIDsData = nil
        self.nextSteps = nil
        self.followUpRequired = false
        self.followUpDate = nil
        self.followUpCompleted = false
    }
}

// MARK: - Enums

extension IssueAction {
    enum IssueActionType: String, Codable, CaseIterable, Sendable {
        case initialReport = "Initial Report"
        case conversation = "Conversation"
        case agreement = "Agreement"
        case followUp = "Follow-up"
        case observation = "Observation"
        case resolution = "Resolution"
        case note = "Note"

        public var systemImage: String {
            switch self {
            case .initialReport: return "flag"
            case .conversation: return "bubble.left.and.bubble.right"
            case .agreement: return "hand.thumbsup"
            case .followUp: return "arrow.turn.up.right"
            case .observation: return "eye"
            case .resolution: return "checkmark.seal"
            case .note: return "note.text"
            }
        }
    }
}

// MARK: - Computed Properties

extension IssueAction {
    var actionType: IssueActionType {
        get { IssueActionType(rawValue: actionTypeRaw) ?? .note }
        set { actionTypeRaw = newValue.rawValue }
    }

    /// Participant student IDs decoded from binary data
    var participantStudentIDs: [String] {
        get { CloudKitStringArrayStorage.decode(from: _participantIDsData) }
        set {
            _participantIDsData = CloudKitStringArrayStorage.encode(newValue)
            updatedAt = Date()
        }
    }
}
