import Foundation
import CoreData

@objc(CDLessonPresentation)
public class CDLessonPresentation: NSManagedObject {
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
    @NSManaged public var followUpActionRaw: String?
    @NSManaged public var followUpReviewAt: Date?
    @NSManaged public var followUpResolvedAt: Date?
    @NSManaged public var followUpResolutionRaw: String?
    @NSManaged public var followUpUpdatedAt: Date?
    @NSManaged public var followUpEvidenceRaw: String?
    @NSManaged public var followUpNote: String?
    @NSManaged public var followUpSupportRaw: String?

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
        self.followUpActionRaw = nil
        self.followUpReviewAt = nil
        self.followUpResolvedAt = nil
        self.followUpResolutionRaw = nil
        self.followUpUpdatedAt = nil
        self.followUpEvidenceRaw = nil
        self.followUpNote = nil
        self.followUpSupportRaw = nil
    }
}

// MARK: - Enums

// MARK: - Computed Properties

extension CDLessonPresentation {
    var state: LessonPresentationState {
        get { LessonPresentationState(rawValue: stateRaw) ?? .presented }
        set { stateRaw = newValue.rawValue }
    }
}
