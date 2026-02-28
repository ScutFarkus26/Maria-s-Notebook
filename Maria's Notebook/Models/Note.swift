import Foundation
import OSLog
import SwiftData

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

@Model
final class Note: Identifiable {
    private static let logger = Logger.database

    #Index<Note>([\.createdAt], [\.searchIndexStudentID], [\.scopeIsAll])
    
    // Identity & timestamps
    var id: UUID = UUID()
    // Indexed for sorting and recent notes queries
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Content
    var body: String = ""
    var isPinned: Bool = false
    // Legacy category field — kept for migration; new code uses `tags`
    private var categoryRaw: String = NoteCategory.general.rawValue
    /// Tags in "Name|Color" format, matching the todo tag system
    var tags: [String] = []
    var includeInReport: Bool = false
    var needsFollowUp: Bool = false
    var imagePath: String? = nil
    
    // Reporter information
    var reportedBy: String? = nil // e.g., "guide", "assistant", "parent"
    var reporterName: String? = nil // e.g., "Mom", "Assistant", etc.
    
    // Legacy computed property — reads from categoryRaw for migration; prefer `tags`
    var category: NoteCategory {
        get { NoteCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }

    /// The legacy categoryRaw value (read-only, for migration)
    var legacyCategoryRaw: String { categoryRaw }

    // Persisted scope storage (JSON-encoded) kept small; no external storage needed
    private var scopeBlob: Data?
    
    // Search index attributes for database-level filtering
    // These are maintained automatically when scope changes
    // Indexed for student-specific note queries
    var searchIndexStudentID: UUID? = nil
    // Indexed for scope-based filtering
    var scopeIsAll: Bool = false

    // Relationships - All possible contexts (only one should be set per note)
    @Relationship var lesson: Lesson?
    @Relationship var work: WorkModel?
    @Relationship var lessonAssignment: LessonAssignment?
    @Relationship var attendanceRecord: AttendanceRecord?
    @Relationship var workCheckIn: WorkCheckIn?
    @Relationship var workCompletionRecord: WorkCompletionRecord?
    @Relationship var studentMeeting: StudentMeeting?
    @Relationship var projectSession: ProjectSession?
    @Relationship var communityTopic: CommunityTopic?
    @Relationship var reminder: Reminder?
    @Relationship var schoolDayOverride: SchoolDayOverride?
    @Relationship var studentTrackEnrollment: StudentTrackEnrollment?
    @Relationship var practiceSession: PracticeSession?
    @Relationship var issue: Issue?

    /// Junction records for efficient multi-student scope queries.
    /// Automatically maintained when scope is set to `.students([UUID])`.
    @Relationship(deleteRule: .cascade, inverse: \NoteStudentLink.note)
    var studentLinks: [NoteStudentLink]? = []

    // Computed, Codable scope
    var scope: NoteScope {
        get {
            let decoded = decodeScope() ?? .all
            // Ensure search index is synced (for existing notes that may not have it set)
            syncSearchIndex(with: decoded)
            return decoded
        }
        set {
            do {
                scopeBlob = try JSONEncoder().encode(newValue)
            } catch {
                Self.logger.warning("Failed to encode scope: \(error.localizedDescription)")
                scopeBlob = nil
            }
            // Update search index attributes for database-level filtering
            syncSearchIndex(with: newValue)
            // Mark that studentLinks need syncing (will be done when context is available)
            _studentLinksNeedSync = true
        }
    }

    /// Internal flag indicating studentLinks need to be synced after scope change.
    /// Call `syncStudentLinksIfNeeded(in:)` after setting scope to complete the sync.
    @Transient private var _studentLinksNeedSync: Bool = false

    /// Returns true if studentLinks need to be synced after a scope change.
    var studentLinksNeedSync: Bool { _studentLinksNeedSync }

    /// Syncs studentLinks if needed and clears the flag. Call this after setting scope.
    @MainActor
    func syncStudentLinksIfNeeded(in context: ModelContext) {
        guard _studentLinksNeedSync else { return }
        syncStudentLinks(in: context)
        _studentLinksNeedSync = false
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
        // Legacy relationship removed — fully migrated to lessonAssignment
        if attendanceRecord != nil { return "attendance" }
        if workCheckIn != nil { return "workCheckIn" }
        if workCompletionRecord != nil { return "workCompletion" }
        // workPlanItem removed in Phase 6 - migrated to WorkCheckIn
        if studentMeeting != nil { return "studentMeeting" }
        if projectSession != nil { return "projectSession" }
        if communityTopic != nil { return "communityTopic" }
        if reminder != nil { return "reminder" }
        if schoolDayOverride != nil { return "schoolDayOverride" }
        if studentTrackEnrollment != nil { return "studentTrackEnrollment" }
        if practiceSession != nil { return "practiceSession" }
        if issue != nil { return "issue" }
        return "general"
    }

    // Initializer with defaults
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        body: String,
        scope: NoteScope = .all,
        isPinned: Bool = false,
        tags: [String] = [],
        includeInReport: Bool = false,
        needsFollowUp: Bool = false,
        lesson: Lesson? = nil,
        work: WorkModel? = nil,
        lessonAssignment: LessonAssignment? = nil,
        attendanceRecord: AttendanceRecord? = nil,
        workCheckIn: WorkCheckIn? = nil,
        workCompletionRecord: WorkCompletionRecord? = nil,
        studentMeeting: StudentMeeting? = nil,
        projectSession: ProjectSession? = nil,
        communityTopic: CommunityTopic? = nil,
        reminder: Reminder? = nil,
        schoolDayOverride: SchoolDayOverride? = nil,
        studentTrackEnrollment: StudentTrackEnrollment? = nil,
        practiceSession: PracticeSession? = nil,
        issue: Issue? = nil,
        imagePath: String? = nil,
        reportedBy: String? = nil,
        reporterName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.body = body
        self.isPinned = isPinned
        self.tags = tags
        self.needsFollowUp = needsFollowUp
        self.includeInReport = includeInReport
        self.lesson = lesson
        self.work = work
        self.lessonAssignment = lessonAssignment
        self.attendanceRecord = attendanceRecord
        self.workCheckIn = workCheckIn
        self.workCompletionRecord = workCompletionRecord
        self.studentMeeting = studentMeeting
        self.projectSession = projectSession
        self.communityTopic = communityTopic
        self.reminder = reminder
        self.schoolDayOverride = schoolDayOverride
        self.studentTrackEnrollment = studentTrackEnrollment
        self.practiceSession = practiceSession
        self.issue = issue
        self.imagePath = imagePath
        self.reportedBy = reportedBy
        self.reporterName = reporterName
        do {
            self.scopeBlob = try JSONEncoder().encode(scope)
        } catch {
            Self.logger.warning("Failed to encode initial scope: \(error.localizedDescription)")
            self.scopeBlob = nil
        }
        // Initialize search index attributes based on scope
        switch scope {
        case .all:
            self.scopeIsAll = true
            self.searchIndexStudentID = nil
        case .student(let id):
            self.scopeIsAll = false
            self.searchIndexStudentID = id
        case .students:
            self.scopeIsAll = false
            self.searchIndexStudentID = nil
            // Mark that studentLinks need syncing after insertion
            self._studentLinksNeedSync = true
        }
    }

    // MARK: - Private helpers
    private func decodeScope() -> NoteScope? {
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
        guard let imagePath = imagePath, !imagePath.isEmpty else { return }
        do {
            try PhotoStorageService.deleteImage(filename: imagePath)
        } catch {
            Self.logger.warning("Failed to delete associated image: \(error.localizedDescription)")
        }
    }

    // MARK: - Student Links Management

    /// Syncs the studentLinks relationship to match the current scope.
    /// Call this after setting scope to `.students([UUID])` and inserting the note.
    /// This enables efficient database-level queries for multi-student scoped notes.
    func syncStudentLinks(in context: ModelContext) {
        let currentScope = decodeScope() ?? .all

        // Clear existing links first
        for link in studentLinks ?? [] {
            context.delete(link)
        }
        studentLinks = []

        // Create new links for multi-student scope
        if case .students(let ids) = currentScope {
            var newLinks: [NoteStudentLink] = []
            for studentID in ids {
                let link = NoteStudentLink(noteID: self.id, studentID: studentID, note: self)
                context.insert(link)
                newLinks.append(link)
            }
            studentLinks = newLinks
        }
    }
}

