import Foundation
import CoreData

@objc(LessonPresentation)
public class LessonPresentation: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var studentID: String
    @NSManaged public var lessonID: String
    @NSManaged public var presentationID: String?
    @NSManaged public var trackID: String?
    @NSManaged public var trackStepID: String?
    @NSManaged public var stateRaw: String
    @NSManaged public var presentedAt: Date?
    @NSManaged public var lastObservedAt: Date?
    @NSManaged public var masteredAt: Date?
    @NSManaged public var notes: String?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "LessonPresentation", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.studentID = ""
        self.lessonID = ""
        self.presentationID = nil
        self.trackID = nil
        self.trackStepID = nil
        self.stateRaw = LessonPresentationState.presented.rawValue
        self.presentedAt = Date()
        self.lastObservedAt = nil
        self.masteredAt = nil
        self.notes = nil
    }
}

// MARK: - Enums

enum LessonPresentationState: String, Codable, CaseIterable, Sendable {
    case presented
    case practicing
    case readyForAssessment
    case proficient = "mastered"
}

// MARK: - Computed Properties

extension LessonPresentation {
    var state: LessonPresentationState {
        get { LessonPresentationState(rawValue: stateRaw) ?? .presented }
        set { stateRaw = newValue.rawValue }
    }
}
