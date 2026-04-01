import Foundation
import CoreData
import OSLog

// MARK: - Enums

// MARK: - Core Data Entity

@objc(CDNote)
public class CDNote: NSManagedObject {
    private static let logger = Logger.database

    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var body: String
    @NSManaged public var isPinned: Bool
    @NSManaged public var categoryRaw: String
    @NSManaged public var tags: NSObject?  // Transformable [String]
    @NSManaged public var includeInReport: Bool
    @NSManaged public var needsFollowUp: Bool
    @NSManaged public var imagePath: String?
    @NSManaged public var reportedBy: String?
    @NSManaged public var reporterName: String?
    @NSManaged public var scopeBlob: Data?
    @NSManaged public var searchIndexStudentID: UUID?
    @NSManaged public var scopeIsAll: Bool

    // MARK: - Cross-Store Foreign Keys (string IDs for Shared entities)
    @NSManaged public var lessonID: String?
    @NSManaged public var communityTopicID: String?
    @NSManaged public var schoolDayOverrideID: String?
    @NSManaged public var studentTrackEnrollmentID: String?
    @NSManaged public var goingOutID: String?
    @NSManaged public var transitionPlanID: String?

    // MARK: - Same-Store Relationships (Private → Private)
    @NSManaged public var work: CDWorkModel?
    @NSManaged public var lessonAssignment: CDLessonAssignment?
    @NSManaged public var attendanceRecord: CDAttendanceRecord?
    @NSManaged public var workCheckIn: CDWorkCheckIn?
    @NSManaged public var workCompletionRecord: CDWorkCompletionRecord?
    @NSManaged public var studentMeeting: CDStudentMeeting?
    @NSManaged public var projectSession: CDProjectSession?
    @NSManaged public var reminder: CDReminder?
    @NSManaged public var practiceSession: CDPracticeSession?
    @NSManaged public var issue: CDIssue?
    @NSManaged public var studentLinks: NSSet?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Note", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.body = ""
        self.isPinned = false
        self.categoryRaw = NoteCategory.general.rawValue
        self.tags = [] as NSArray
        self.includeInReport = false
        self.needsFollowUp = false
        self.imagePath = nil
        self.reportedBy = nil
        self.reporterName = nil
        self.scopeBlob = nil
        self.searchIndexStudentID = nil
        self.scopeIsAll = false
    }
}

// MARK: - Computed Properties

extension CDNote {
    /// Access tags as a Swift [String] array
    var tagsArray: [String] {
        get { (tags as? [String]) ?? [] }
        set { tags = newValue as NSArray }
    }

    // Legacy computed property -- reads from categoryRaw for migration; prefer `tags`
    var category: NoteCategory {
        get { NoteCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }

    /// The legacy categoryRaw value (read-only, for migration)
    var legacyCategoryRaw: String { categoryRaw }

    // Computed, Codable scope
    var scope: NoteScope {
        get {
            decodeScope() ?? .all
        }
        set {
            do {
                scopeBlob = try JSONEncoder().encode(newValue)
            } catch {
                Self.logger.error("Failed to encode scope: \(error.localizedDescription)")
            }
            syncSearchIndex(with: newValue)
        }
    }

    // Helper to sync search index attributes with scope
    private func syncSearchIndex(with scope: NoteScope) {
        switch scope {
        case .all:
            scopeIsAll = true
            searchIndexStudentID = nil
        case .student(let id):
            scopeIsAll = false
            searchIndexStudentID = id
        case .students:
            scopeIsAll = false
            searchIndexStudentID = nil
        }
    }

    // Helper to identify which context this note belongs to
    var attachedTo: String {
        if lessonID != nil { return "lesson" }
        if work != nil { return "work" }
        if lessonAssignment != nil { return "presentation" }
        if attendanceRecord != nil { return "attendance" }
        if workCheckIn != nil { return "workCheckIn" }
        if workCompletionRecord != nil { return "workCompletion" }
        if studentMeeting != nil { return "studentMeeting" }
        if projectSession != nil { return "projectSession" }
        if communityTopicID != nil { return "communityTopic" }
        if reminder != nil { return "reminder" }
        if schoolDayOverrideID != nil { return "schoolDayOverride" }
        if studentTrackEnrollmentID != nil { return "studentTrackEnrollment" }
        if practiceSession != nil { return "practiceSession" }
        if issue != nil { return "issue" }
        if goingOutID != nil { return "goingOut" }
        if transitionPlanID != nil { return "transitionPlan" }
        return "general"
    }

    // MARK: - Helpers

    func decodeScope() -> NoteScope? {
        guard let data = scopeBlob else { return nil }
        do {
            return try JSONDecoder().decode(NoteScope.self, from: data)
        } catch {
            Self.logger.warning("Failed to decode scope: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Image Management

    /// Deletes the associated image file from disk if one exists.
    /// Call this before deleting the CDNote to prevent orphaned images.
    func deleteAssociatedImage() {
        guard let imagePath, !imagePath.isEmpty else { return }
        do {
            try PhotoStorageService.deleteImage(filename: imagePath)
        } catch {
            Self.logger.warning("Failed to delete associated image: \(error.localizedDescription)")
        }
    }
}

// MARK: - Cross-Store Relationship Accessors (fetch via FK)

extension CDNote {
    var lesson: CDLesson? {
        get {
            guard let lessonID, let ctx = managedObjectContext else { return nil }
            let req = CDFetchRequest(CDLesson.self)
            req.predicate = NSPredicate(format: "id == %@", lessonID)
            req.fetchLimit = 1
            return ctx.safeFetchFirst(req)
        }
        set { lessonID = newValue?.id?.uuidString }
    }

    var communityTopic: CDCommunityTopicEntity? {
        get {
            guard let communityTopicID, let ctx = managedObjectContext else { return nil }
            let req = CDFetchRequest(CDCommunityTopicEntity.self)
            req.predicate = NSPredicate(format: "id == %@", communityTopicID)
            req.fetchLimit = 1
            return ctx.safeFetchFirst(req)
        }
        set { communityTopicID = newValue?.id?.uuidString }
    }

    var schoolDayOverride: CDSchoolDayOverride? {
        get {
            guard let schoolDayOverrideID, let ctx = managedObjectContext else { return nil }
            let req = CDFetchRequest(CDSchoolDayOverride.self)
            req.predicate = NSPredicate(format: "id == %@", schoolDayOverrideID)
            req.fetchLimit = 1
            return ctx.safeFetchFirst(req)
        }
        set { schoolDayOverrideID = newValue?.id?.uuidString }
    }

    var studentTrackEnrollment: CDStudentTrackEnrollmentEntity? {
        get {
            guard let studentTrackEnrollmentID, let ctx = managedObjectContext else { return nil }
            let req = CDFetchRequest(CDStudentTrackEnrollmentEntity.self)
            req.predicate = NSPredicate(format: "id == %@", studentTrackEnrollmentID)
            req.fetchLimit = 1
            return ctx.safeFetchFirst(req)
        }
        set { studentTrackEnrollmentID = newValue?.id?.uuidString }
    }

    var goingOut: CDGoingOut? {
        get {
            guard let goingOutID, let ctx = managedObjectContext else { return nil }
            let req = CDFetchRequest(CDGoingOut.self)
            req.predicate = NSPredicate(format: "id == %@", goingOutID)
            req.fetchLimit = 1
            return ctx.safeFetchFirst(req)
        }
        set { goingOutID = newValue?.id?.uuidString }
    }

    var transitionPlan: CDTransitionPlan? {
        get {
            guard let transitionPlanID, let ctx = managedObjectContext else { return nil }
            let req = CDFetchRequest(CDTransitionPlan.self)
            req.predicate = NSPredicate(format: "id == %@", transitionPlanID)
            req.fetchLimit = 1
            return ctx.safeFetchFirst(req)
        }
        set { transitionPlanID = newValue?.id?.uuidString }
    }
}

// MARK: - Generated Accessors for To-Many Relationships

extension CDNote {
    @objc(addStudentLinksObject:)
    @NSManaged public func addToStudentLinks(_ value: CDNoteStudentLink)

    @objc(removeStudentLinksObject:)
    @NSManaged public func removeFromStudentLinks(_ value: CDNoteStudentLink)

    @objc(addStudentLinks:)
    @NSManaged public func addToStudentLinks(_ values: NSSet)

    @objc(removeStudentLinks:)
    @NSManaged public func removeFromStudentLinks(_ values: NSSet)
}
