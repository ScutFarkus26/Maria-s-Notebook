import Foundation
import CoreData
import OSLog

// MARK: - Enums

public enum NoteCategory: String, Codable, CaseIterable {
    case academic
    case behavioral
    case social
    case emotional
    case health
    case attendance
    case general
}

enum NoteScope: Codable, Equatable {
    case all
    case student(UUID)
    case students([UUID])

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case ids
    }

    enum ScopeType: String, Codable {
        case all
        case student
        case students
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ScopeType.self, forKey: .type)
        switch type {
        case .all:
            self = .all
        case .student:
            let id = try container.decode(UUID.self, forKey: .id)
            self = .student(id)
        case .students:
            let ids = try container.decode([UUID].self, forKey: .ids)
            self = .students(ids)
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all:
            try container.encode(ScopeType.all, forKey: .type)
            try container.encodeNil(forKey: .id)
            try container.encodeNil(forKey: .ids)
        case .student(let id):
            try container.encode(ScopeType.student, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeNil(forKey: .ids)
        case .students(let ids):
            try container.encode(ScopeType.students, forKey: .type)
            try container.encodeNil(forKey: .id)
            try container.encode(ids, forKey: .ids)
        }
    }

    var isAll: Bool {
        if case .all = self {
            return true
        }
        return false
    }

    func applies(to studentID: UUID) -> Bool {
        switch self {
        case .all:
            return true
        case .student(let id):
            return id == studentID
        case .students(let ids):
            return ids.contains(studentID)
        }
    }
}

// MARK: - Core Data Entity

@objc(Note)
public class Note: NSManagedObject {
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
    @NSManaged public var lesson: Lesson?
    @NSManaged public var work: WorkModel?
    @NSManaged public var lessonAssignment: LessonAssignment?
    @NSManaged public var attendanceRecord: AttendanceRecord?
    @NSManaged public var workCheckIn: WorkCheckIn?
    @NSManaged public var workCompletionRecord: WorkCompletionRecord?
    @NSManaged public var studentMeeting: StudentMeeting?
    @NSManaged public var projectSession: ProjectSession?
    @NSManaged public var communityTopic: CommunityTopic?
    @NSManaged public var reminder: Reminder?
    @NSManaged public var schoolDayOverride: SchoolDayOverride?
    @NSManaged public var studentTrackEnrollment: StudentTrackEnrollment?
    @NSManaged public var practiceSession: PracticeSession?
    @NSManaged public var issue: Issue?
    @NSManaged public var goingOut: GoingOut?
    @NSManaged public var transitionPlan: TransitionPlan?
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

extension Note {
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

extension Note {
    @objc(addStudentLinksObject:)
    @NSManaged public func addToStudentLinks(_ value: NoteStudentLink)

    @objc(removeStudentLinksObject:)
    @NSManaged public func removeFromStudentLinks(_ value: NoteStudentLink)

    @objc(addStudentLinks:)
    @NSManaged public func addToStudentLinks(_ values: NSSet)

    @objc(removeStudentLinks:)
    @NSManaged public func removeFromStudentLinks(_ values: NSSet)
}
