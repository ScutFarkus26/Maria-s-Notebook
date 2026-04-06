import Foundation
import CoreData

@objc(CDLesson)
public class CDLesson: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var name: String
    @NSManaged public var subject: String
    @NSManaged public var group: String
    @NSManaged public var orderInGroup: Int64
    @NSManaged public var sortIndex: Int64
    @NSManaged public var subheading: String
    @NSManaged public var writeUp: String
    @NSManaged public var suggestedFollowUpWork: String
    @NSManaged public var materials: String
    @NSManaged public var purpose: String
    @NSManaged public var ageRange: String
    @NSManaged public var teacherNotes: String
    @NSManaged public var prerequisiteLessonIDs: String
    @NSManaged public var relatedLessonIDs: String
    @NSManaged public var greatLessonRaw: String?
    @NSManaged public var sourceRaw: String
    @NSManaged public var personalKindRaw: String?
    @NSManaged public var lessonFormatRaw: String
    @NSManaged public var parentStoryID: String?
    @NSManaged public var defaultWorkKindRaw: String?
    @NSManaged public var pagesFileBookmark: Data?
    @NSManaged public var pagesFileRelativePath: String?
    @NSManaged public var primaryAttachmentID: String?
    @NSManaged public var requiresPracticeOverride: String
    @NSManaged public var requiresConfirmationOverride: String

    // MARK: - Relationships
    @NSManaged public var attachments: NSSet?
    @NSManaged public var sampleWorks: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Lesson", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.name = ""
        self.subject = ""
        self.group = ""
        self.orderInGroup = 0
        self.sortIndex = 0
        self.subheading = ""
        self.writeUp = ""
        self.suggestedFollowUpWork = ""
        self.materials = ""
        self.purpose = ""
        self.ageRange = ""
        self.teacherNotes = ""
        self.prerequisiteLessonIDs = ""
        self.relatedLessonIDs = ""
        self.greatLessonRaw = nil
        self.sourceRaw = "album"
        self.personalKindRaw = nil
        self.lessonFormatRaw = "standard"
        self.parentStoryID = nil
        self.defaultWorkKindRaw = nil
        self.pagesFileBookmark = nil
        self.pagesFileRelativePath = nil
        self.primaryAttachmentID = nil
        self.requiresPracticeOverride = "inherit"
        self.requiresConfirmationOverride = "inherit"
    }
}

// MARK: - Computed Properties

extension CDLesson {
    var source: LessonSource {
        get { LessonSource(rawValue: sourceRaw) ?? .album }
        set { sourceRaw = newValue.rawValue }
    }

    var personalKind: PersonalLessonKind? {
        get {
            guard source == .personal else { return nil }
            guard let raw = personalKindRaw else { return .personal }
            return PersonalLessonKind(rawValue: raw) ?? .personal
        }
        set {
            if source != .personal { personalKindRaw = nil; return }
            personalKindRaw = (newValue ?? .personal).rawValue
        }
    }

    /// The preferred work kind for this lesson.
    var defaultWorkKind: WorkKind? {
        get { defaultWorkKindRaw.flatMap { WorkKind(rawValue: $0) } }
        set { defaultWorkKindRaw = newValue?.rawValue }
    }

    /// Computed Great CDLesson enum value
    var greatLesson: GreatLesson? {
        get { greatLessonRaw.flatMap { GreatLesson(rawValue: $0) } }
        set { greatLessonRaw = newValue?.rawValue }
    }

    var lessonFormat: LessonFormat {
        get { LessonFormat(rawValue: lessonFormatRaw) ?? .standard }
        set { lessonFormatRaw = newValue.rawValue }
    }

    var parentStoryUUID: UUID? {
        get { parentStoryID.flatMap(UUID.init(uuidString:)) }
        set { parentStoryID = newValue?.uuidString }
    }

    /// Whether this lesson is a story (root or child).
    var isStory: Bool { lessonFormat == .story }

    /// Whether this lesson is a top-level story with no parent.
    var isRootStory: Bool { isStory && parentStoryID == nil }

    var primaryAttachmentIDUUID: UUID? {
        get { primaryAttachmentID.flatMap(UUID.init(uuidString:)) }
        set { primaryAttachmentID = newValue?.uuidString }
    }

    /// Helper to access suggested follow-up work as an array of individual items
    var suggestedFollowUpWorkItems: [String] {
        suggestedFollowUpWork
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Helper to access materials as an array of individual items
    var materialsItems: [String] {
        materials
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Parsed prerequisite lesson UUIDs
    var prerequisiteLessonUUIDs: [UUID] {
        get {
            prerequisiteLessonIDs
                .components(separatedBy: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
        set {
            prerequisiteLessonIDs = newValue.map(\.uuidString).joined(separator: ",")
        }
    }

    /// Parsed related lesson UUIDs
    var relatedLessonUUIDs: [UUID] {
        get {
            relatedLessonIDs
                .components(separatedBy: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
        set {
            relatedLessonIDs = newValue.map(\.uuidString).joined(separator: ",")
        }
    }

    /// Cross-store inverse: fetches Notes whose lessonID matches this lesson.
    var notes: [CDNote] {
        guard let id, let ctx = managedObjectContext else { return [] }
        let req = CDFetchRequest(CDNote.self)
        req.predicate = NSPredicate(format: "lessonID == %@", id.uuidString)
        return (try? ctx.fetch(req)) ?? []
    }

    /// Cross-store inverse: fetches LessonAssignments whose lessonID matches this lesson.
    var lessonAssignments: [CDLessonAssignment] {
        guard let id, let ctx = managedObjectContext else { return [] }
        let req = CDFetchRequest(CDLessonAssignment.self)
        req.predicate = NSPredicate(format: "lessonID == %@", id.uuidString)
        return (try? ctx.fetch(req)) ?? []
    }

    /// Progression rule override for requiring practice.
    var practiceOverride: ProgressionOverride {
        get { ProgressionOverride(rawValue: requiresPracticeOverride) ?? .inherit }
        set { requiresPracticeOverride = newValue.rawValue }
    }

    /// Progression rule override for requiring teacher confirmation.
    var confirmationOverride: ProgressionOverride {
        get { ProgressionOverride(rawValue: requiresConfirmationOverride) ?? .inherit }
        set { requiresConfirmationOverride = newValue.rawValue }
    }

    /// Sample works sorted by orderIndex
    var orderedSampleWorks: [CDSampleWorkEntity] {
        ((sampleWorks?.allObjects as? [CDSampleWorkEntity]) ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDLesson {
    @objc(addAttachmentsObject:)
    @NSManaged public func addToAttachments(_ value: CDLessonAttachment)

    @objc(removeAttachmentsObject:)
    @NSManaged public func removeFromAttachments(_ value: CDLessonAttachment)

    @objc(addAttachments:)
    @NSManaged public func addToAttachments(_ values: NSSet)

    @objc(removeAttachments:)
    @NSManaged public func removeFromAttachments(_ values: NSSet)

    @objc(addSampleWorksObject:)
    @NSManaged public func addToSampleWorks(_ value: CDSampleWorkEntity)

    @objc(removeSampleWorksObject:)
    @NSManaged public func removeFromSampleWorks(_ value: CDSampleWorkEntity)

    @objc(addSampleWorks:)
    @NSManaged public func addToSampleWorks(_ values: NSSet)

    @objc(removeSampleWorks:)
    @NSManaged public func removeFromSampleWorks(_ values: NSSet)
}
