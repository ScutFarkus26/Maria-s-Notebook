import Foundation
import SwiftData

/// General-purpose note not attached to a specific primary entity.
///
/// **Type Safety:** No required relationship (standalone notes)
/// **Optional Links:** Can link to CommunityTopic, Reminder, Issue, etc.
/// **Use Cases:**
/// - Standalone notes
/// - Community discussion notes
/// - Reminder notes
/// - Issue tracking notes
/// - School day override notes
/// - Track enrollment notes
/// - Practice session notes
///
/// **Migration:** Created from Note where no primary relationship exists, or for secondary entities
@Model
final class GeneralNote: NoteProtocol {
    // MARK: - Identity
    var id: UUID = UUID()
    
    // MARK: - Content
    var content: String = ""
    
    // MARK: - Metadata
    var createdAt: Date = Date()
    var modifiedAt: Date? = nil
    var authorID: UUID? = nil
    
    // MARK: - Category
    private var categoryRaw: String = NoteCategory.general.rawValue
    var category: NoteCategory {
        get { NoteCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }
    
    // MARK: - Optional Context Links
    /// Optional: Links to CommunityTopic
    var communityTopicID: String? = nil
    
    /// Optional: Links to Reminder
    var reminderID: String? = nil
    
    /// Optional: Links to Issue
    var issueID: String? = nil
    
    /// Optional: Links to SchoolDayOverride
    var schoolDayOverrideID: String? = nil
    
    /// Optional: Links to StudentTrackEnrollment
    var trackEnrollmentID: String? = nil
    
    /// Optional: Links to PracticeSession
    var practiceSessionID: String? = nil
    
    // MARK: - Scope (for standalone notes)
    /// Scope blob for JSON encoding (stores NoteScope enum)
    @Attribute(.externalStorage) private var scopeBlob: Data?
    
    /// Note scope (all students, single student, or multiple students)
    var scope: NoteScope {
        get {
            guard let scopeBlob = scopeBlob,
                  let decoded = try? JSONDecoder().decode(NoteScope.self, from: scopeBlob) else {
                return .all
            }
            return decoded
        }
        set {
            scopeBlob = try? JSONEncoder().encode(newValue)
        }
    }
    
    // MARK: - Initialization
    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        authorID: UUID? = nil,
        category: NoteCategory = .general,
        scope: NoteScope = .all,
        communityTopicID: String? = nil,
        reminderID: String? = nil,
        issueID: String? = nil,
        schoolDayOverrideID: String? = nil,
        trackEnrollmentID: String? = nil,
        practiceSessionID: String? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.authorID = authorID
        self.categoryRaw = category.rawValue
        self.scope = scope
        self.communityTopicID = communityTopicID
        self.reminderID = reminderID
        self.issueID = issueID
        self.schoolDayOverrideID = schoolDayOverrideID
        self.trackEnrollmentID = trackEnrollmentID
        self.practiceSessionID = practiceSessionID
    }
}
