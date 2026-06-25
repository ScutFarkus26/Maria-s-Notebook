import Foundation
import CoreData

@objc(CDLessonRecallCheck)
public class CDLessonRecallCheck: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var studentID: String
    @NSManaged public var lessonID: String
    @NSManaged public var outcomeRaw: String
    @NSManaged public var sourceRaw: String
    @NSManaged public var coveredByLessonID: String?
    @NSManaged public var presentationID: String?
    @NSManaged public var originalMasteredAt: Date?
    @NSManaged public var checkedAt: Date?
    @NSManaged public var note: String?
    @NSManaged public var photoRef: String?
    @NSManaged public var schoolYearKey: String?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "LessonRecallCheck", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.studentID = ""
        self.lessonID = ""
        self.outcomeRaw = RecallOutcome.retained.rawValue
        self.sourceRaw = RecallSource.observed.rawValue
        self.coveredByLessonID = nil
        self.presentationID = nil
        self.originalMasteredAt = nil
        self.checkedAt = Date()
        self.note = nil
        self.photoRef = nil
        self.schoolYearKey = nil
    }
}

// MARK: - Enums

/// The result of a recall check. Three user-facing outcomes.
enum RecallOutcome: String, CaseIterable, Sendable {
    case retained   // "still has it"
    case shaky      // needs a quick brush-up
    case forgotten  // needs a re-presentation
}

/// How a recall record came to be: a check the guide actually ran, or an inference
/// from a more-advanced retained lesson that covers this one within the same strand.
enum RecallSource: String, CaseIterable, Sendable {
    case observed
    case covered
}

// MARK: - Computed Properties

extension CDLessonRecallCheck {
    var outcome: RecallOutcome {
        get { RecallOutcome(rawValue: outcomeRaw) ?? .retained }
        set { outcomeRaw = newValue.rawValue }
    }

    var source: RecallSource {
        get { RecallSource(rawValue: sourceRaw) ?? .observed }
        set { sourceRaw = newValue.rawValue }
    }
}
