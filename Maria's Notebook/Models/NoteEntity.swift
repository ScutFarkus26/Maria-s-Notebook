import Foundation
import CoreData
import OSLog

// MARK: - Enums

// MARK: - Core Data Entity

@objc(Note)
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

    // MARK: - Relationships
    @NSManaged public var lesson: CDLesson?
    @NSManaged public var work: CDWorkModel?
    @NSManaged public var lessonAssignment: CDLessonAssignment?
    @NSManaged public var attendanceRecord: CDAttendanceRecord?
    @NSManaged public var workCheckIn: CDWorkCheckIn?
    @NSManaged public var workCompletionRecord: CDWorkCompletionRecord?
    @NSManaged public var studentMeeting: CDStudentMeeting?
    @NSManaged public var projectSession: CDProjectSession?
    @NSManaged public var communityTopic: CDCommunityTopicEntity?
    @NSManaged public var reminder: CDReminder?
    @NSManaged public var schoolDayOverride: CDSchoolDayOverride?
    @NSManaged public var studentTrackEnrollment: CDStudentTrackEnrollmentEntity?
    @NSManaged public var practiceSession: CDPracticeSession?
    @NSManaged public var issue: CDIssue?
    @NSManaged public var goingOut: CDGoingOut?
    @NSManaged public var transitionPlan: CDTransitionPlan?
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
        if lesson != nil { return "lesson" }
        if work != nil { return "work" }
        if lessonAssignment != nil { return "presentation" }
        if attendanceRecord != nil { return "attendance" }
        if workCheckIn != nil { return "workCheckIn" }
        if workCompletionRecord != nil { return "workCompletion" }
        if studentMeeting != nil { return "studentMeeting" }
        if projectSession != nil { return "projectSession" }
        if communityTopic != nil { return "communityTopic" }
        if reminder != nil { return "reminder" }
        if schoolDayOverride != nil { return "schoolDayOverride" }
        if studentTrackEnrollment != nil { return "studentTrackEnrollment" }
        if practiceSession != nil { return "practiceSession" }
        if issue != nil { return "issue" }
        if goingOut != nil { return "goingOut" }
        if transitionPlan != nil { return "transitionPlan" }
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
    /// Call this before deleting the Note to prevent orphaned images.
    func deleteAssociatedImage() {
        guard let imagePath, !imagePath.isEmpty else { return }
        do {
            try PhotoStorageService.deleteImage(filename: imagePath)
        } catch {
            Self.logger.warning("Failed to delete associated image: \(error.localizedDescription)")
        }
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
