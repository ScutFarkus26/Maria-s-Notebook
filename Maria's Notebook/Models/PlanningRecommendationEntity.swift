import Foundation
import CoreData

@objc(PlanningRecommendation)
public class PlanningRecommendation: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var lessonID: String
    @NSManaged public var _studentIDsData: Data?
    @NSManaged public var reasoning: String
    @NSManaged public var confidence: Double
    @NSManaged public var priority: Int64
    @NSManaged public var subjectContext: String
    @NSManaged public var groupContext: String
    @NSManaged public var planningSessionID: String
    @NSManaged public var depthLevel: String
    @NSManaged public var decisionRaw: String?
    @NSManaged public var decisionAt: Date?
    @NSManaged public var teacherNote: String?
    @NSManaged public var outcomeRaw: String?
    @NSManaged public var outcomeRecordedAt: Date?
    @NSManaged public var presentationID: String?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "PlanningRecommendation", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.lessonID = ""
        self._studentIDsData = nil
        self.reasoning = ""
        self.confidence = 0.0
        self.priority = 0
        self.subjectContext = ""
        self.groupContext = ""
        self.planningSessionID = ""
        self.depthLevel = ""
        self.decisionRaw = nil
        self.decisionAt = nil
        self.teacherNote = nil
        self.outcomeRaw = nil
        self.outcomeRecordedAt = nil
        self.presentationID = nil
    }
}

// MARK: - Enums

extension PlanningRecommendation {
    /// Teacher decision on a recommendation
    enum TeacherDecision: String, Codable, Sendable {
        case accepted
        case rejected
        case modified
        case deferred
    }

    /// Outcome after a recommendation was accepted and applied
    enum RecommendationOutcome: String, Codable, Sendable {
        case presented
        case deferred
        case cancelled
        case modified
    }
}

// MARK: - Computed Properties

extension PlanningRecommendation {
    /// Student IDs decoded from binary data
    var studentIDs: [String] {
        get { CloudKitStringArrayStorage.decode(from: _studentIDsData) }
        set { _studentIDsData = CloudKitStringArrayStorage.encode(newValue) }
    }

    var decision: TeacherDecision? {
        get {
            guard let raw = decisionRaw else { return nil }
            return TeacherDecision(rawValue: raw)
        }
        set {
            decisionRaw = newValue?.rawValue
            if newValue != nil {
                decisionAt = Date()
                modifiedAt = Date()
            }
        }
    }

    var outcome: RecommendationOutcome? {
        get {
            guard let raw = outcomeRaw else { return nil }
            return RecommendationOutcome(rawValue: raw)
        }
        set {
            outcomeRaw = newValue?.rawValue
            if newValue != nil {
                outcomeRecordedAt = Date()
                modifiedAt = Date()
            }
        }
    }

    var lessonIDUUID: UUID? {
        UUID(uuidString: lessonID)
    }

    var studentUUIDs: [UUID] {
        studentIDs.compactMap { UUID(uuidString: $0) }
    }
}
