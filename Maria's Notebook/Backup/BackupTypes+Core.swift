import Foundation

// MARK: - Core DTOs (Students, Lessons, Notes, and closely related types)

public struct ItemDTO: Codable, Sendable {
    public var id: UUID
    public var timestamp: Date
}

public struct StudentDTO: Codable, Sendable {
    public enum Level: String, Codable, Sendable { case lower, upper }
    public var id: UUID
    public var firstName: String
    public var lastName: String
    public var birthday: Date
    public var dateStarted: Date?
    public var level: Level
    public var nextLessons: [UUID]
    public var manualOrder: Int
    public var createdAt: Date?
    public var updatedAt: Date?
}

public struct LessonDTO: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var subject: String
    public var group: String
    public var orderInGroup: Int
    public var subheading: String
    public var writeUp: String
    public var createdAt: Date?
    public var updatedAt: Date?
    // File-related fields are intentionally omitted; only include managed relative path if needed
    public var pagesFileRelativePath: String?
    // Montessori album fields (format v9+)
    public var suggestedFollowUpWork: String?
    public var sourceRaw: String?
    public var personalKindRaw: String?
    public var defaultWorkKindRaw: String?
    public var materials: String?
    public var purpose: String?
    public var ageRange: String?
    public var teacherNotes: String?
    public var prerequisiteLessonIDs: String?
    public var relatedLessonIDs: String?
}

public struct LessonExerciseDTO: Codable, Sendable {
    public var id: UUID
    public var lessonID: UUID?
    public var orderIndex: Int
    public var title: String
    public var preparation: String
    public var presentationSteps: String
    public var notes: String
    public var createdAt: Date
}

public struct LessonAttachmentDTO: Codable, Sendable {
    public var id: UUID
    public var fileName: String
    public var fileRelativePath: String
    public var attachedAt: Date
    public var fileType: String
    public var fileSizeBytes: Int64
    public var scopeRaw: String
    public var notes: String
    public var lessonID: UUID?
    // Binary data (fileBookmark, thumbnailData) excluded by design
}

public struct LessonPresentationDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var studentID: String
    public var lessonID: String
    public var presentationID: String?
    public var trackID: String?
    public var trackStepID: String?
    public var stateRaw: String
    public var presentedAt: Date
    public var lastObservedAt: Date?
    public var masteredAt: Date?
    public var notes: String?
}

public struct LegacyPresentationDTO: Codable, Sendable {
    public var id: UUID
    public var lessonID: UUID
    public var studentIDs: [UUID]
    public var createdAt: Date
    public var scheduledFor: Date?
    public var givenAt: Date?
    public var isPresented: Bool
    public var notes: String
    public var needsPractice: Bool
    public var needsAnotherPresentation: Bool
    public var followUpWork: String
    public var studentGroupKey: String?
}

// MARK: - LessonAssignment DTO
/// DTO for the unified LessonAssignment model.
/// This model replaces LegacyPresentation + Presentation in the new architecture.
public struct LessonAssignmentDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var stateRaw: String
    public var scheduledFor: Date?
    public var presentedAt: Date?
    public var lessonID: String
    public var studentIDs: [String]
    public var lessonTitleSnapshot: String?
    public var lessonSubheadingSnapshot: String?
    public var needsPractice: Bool
    public var needsAnotherPresentation: Bool
    public var followUpWork: String
    public var notes: String
    public var trackID: String?
    public var trackStepID: String?
    public var migratedFromLegacyID: String?
    public var migratedFromPresentationID: String?

    public init(
        id: UUID,
        createdAt: Date,
        modifiedAt: Date,
        stateRaw: String,
        scheduledFor: Date?,
        presentedAt: Date?,
        lessonID: String,
        studentIDs: [String],
        lessonTitleSnapshot: String?,
        lessonSubheadingSnapshot: String?,
        needsPractice: Bool,
        needsAnotherPresentation: Bool,
        followUpWork: String,
        notes: String,
        trackID: String?,
        trackStepID: String?,
        migratedFromLegacyID: String?,
        migratedFromPresentationID: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.stateRaw = stateRaw
        self.scheduledFor = scheduledFor
        self.presentedAt = presentedAt
        self.lessonID = lessonID
        self.studentIDs = studentIDs
        self.lessonTitleSnapshot = lessonTitleSnapshot
        self.lessonSubheadingSnapshot = lessonSubheadingSnapshot
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
        self.notes = notes
        self.trackID = trackID
        self.trackStepID = trackStepID
        self.migratedFromLegacyID = migratedFromLegacyID
        self.migratedFromPresentationID = migratedFromPresentationID
    }
}

public struct NoteDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var body: String
    public var isPinned: Bool
    public var scope: String // serialized enum value
    public var tags: [String]?
    public var needsFollowUp: Bool?
    public var lessonID: UUID?
    public var workID: UUID?
    public var imagePath: String?
}

public struct NonSchoolDayDTO: Codable, Sendable {
    public var id: UUID
    public var date: Date
    public var reason: String?
}

public struct SchoolDayOverrideDTO: Codable, Sendable {
    public var id: UUID
    public var date: Date
}

public struct CommunityTopicDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var issueDescription: String
    public var createdAt: Date
    public var addressedDate: Date?
    public var resolution: String
    public var raisedBy: String
    public var tags: [String]
}

public struct ProposedSolutionDTO: Codable, Sendable {
    public var id: UUID
    public var topicID: UUID?
    public var title: String
    public var details: String
    public var proposedBy: String
    public var createdAt: Date
    public var isAdopted: Bool
}

public struct CommunityAttachmentDTO: Codable, Sendable {
    public var id: UUID
    public var topicID: UUID?
    public var filename: String
    public var kind: String
    // Do not include raw data; metadata only
    public var createdAt: Date
}

// MARK: - Template DTOs

public struct NoteTemplateDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var body: String
    public var categoryRaw: String
    public var tags: [String]?
    public var sortOrder: Int
    public var isBuiltIn: Bool
}

public struct MeetingTemplateDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var name: String
    public var reflectionPrompt: String
    public var focusPrompt: String
    public var requestsPrompt: String
    public var guideNotesPrompt: String
    public var sortOrder: Int
    public var isActive: Bool
    public var isBuiltIn: Bool
}
