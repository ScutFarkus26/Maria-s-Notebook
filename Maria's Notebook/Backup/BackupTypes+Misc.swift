import Foundation

// MARK: - Todo DTOs

public struct TodoItemDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var isCompleted: Bool
    public var createdAt: Date
    public var completedAt: Date?
    public var orderIndex: Int
    public var dueDate: Date?
    public var priorityRaw: String
    public var recurrenceRaw: String
    public var studentIDs: [String]
    public var linkedWorkItemID: String?
    public var attachmentPaths: [String]
    public var estimatedMinutes: Int?
    public var actualMinutes: Int?
    public var reminderDate: Date?
    public var reflectionNotes: String
    public var tags: [String]
    // CDSchedule fields
    public var scheduledDate: Date?
    public var isSomeday: Bool?
    public var repeatAfterCompletion: Bool?
    public var customIntervalDays: Int?
    // Location fields
    public var locationName: String?
    public var locationLatitude: Double?
    public var locationLongitude: Double?
    public var locationRadius: Double
    public var notifyOnEntry: Bool
    public var notifyOnExit: Bool
}

public struct TodoSubtaskDTO: Codable, Sendable {
    public var id: UUID
    public var todoID: UUID?
    public var title: String
    public var isCompleted: Bool
    public var orderIndex: Int
    public var createdAt: Date
    public var completedAt: Date?
}

public struct TodoTemplateDTO: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var title: String
    public var notes: String
    public var createdAt: Date
    public var priorityRaw: String
    public var defaultEstimatedMinutes: Int?
    public var defaultStudentIDs: [String]
    public var useCount: Int
    public var tags: [String]?
}

// MARK: - CDTrackEntity DTOs

public struct TrackDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
}

public struct TrackStepDTO: Codable, Sendable {
    public var id: UUID
    public var trackID: UUID?
    public var orderIndex: Int
    public var lessonTemplateID: UUID?
    public var createdAt: Date
}

public struct StudentTrackEnrollmentDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var studentID: String
    public var trackID: String
    public var startedAt: Date?
    public var isActive: Bool
}

public struct GroupTrackDTO: Codable, Sendable {
    public var id: UUID
    public var subject: String
    public var group: String
    public var isSequential: Bool
    public var isExplicitlyDisabled: Bool
    public var createdAt: Date
}

// MARK: - Development Snapshot DTO

public struct DevelopmentSnapshotDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var generatedAt: Date
    public var lookbackDays: Int
    public var analysisVersion: String
    public var overallProgress: String
    public var keyStrengths: [String]
    public var areasForGrowth: [String]
    public var developmentalMilestones: [String]
    public var observedPatterns: [String]
    public var behavioralTrends: [String]
    public var socialEmotionalInsights: [String]
    public var recommendedNextLessons: [String]
    public var suggestedPracticeFocus: [String]
    public var interventionSuggestions: [String]
    public var totalNotesAnalyzed: Int
    public var practiceSessionsAnalyzed: Int
    public var workCompletionsAnalyzed: Int
    public var averagePracticeQuality: Double?
    public var independenceLevel: Double?
    public var rawAnalysisJSON: String
    public var userNotes: String
    public var isReviewed: Bool
    public var sharedWithParents: Bool
    public var sharedAt: Date?
}

// MARK: - CDSupply DTOs

public struct SupplyDTO: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var categoryRaw: String
    public var location: String
    public var currentQuantity: Int
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date
}

// MARK: - CDDocument DTO

public struct DocumentDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var category: String
    public var uploadDate: Date
    public var studentID: UUID?
    // PDF data excluded by design - too large for JSON backup
}

// MARK: - Agenda Order DTO

public struct TodayAgendaOrderDTO: Codable, Sendable {
    public var id: UUID
    public var day: Date
    public var itemTypeRaw: String
    public var itemID: UUID
    public var position: Int
}

// MARK: - Going Out DTOs (format v12+)

public struct GoingOutDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var title: String
    public var purpose: String
    public var destination: String
    public var proposedDate: Date?
    public var actualDate: Date?
    public var statusRaw: String
    public var studentIDs: [String]
    public var curriculumLinkIDs: String
    public var permissionStatusRaw: String
    public var notes: String
    public var followUpWork: String
    public var supervisorName: String
}

public struct GoingOutChecklistItemDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var goingOutID: String
    public var title: String
    public var isCompleted: Bool
    public var sortOrder: Int
    public var assignedToStudentID: String?
}

// MARK: - Classroom Job DTOs (format v12+)

public struct ClassroomJobDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var name: String
    public var jobDescription: String
    public var icon: String
    public var colorRaw: String
    public var sortOrder: Int
    public var isActive: Bool
    public var maxStudents: Int
}

public struct JobAssignmentDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var jobID: String
    public var studentID: String
    public var weekStartDate: Date
    public var isCompleted: Bool
}

// MARK: - Transition Plan DTOs (format v12+)

public struct TransitionPlanDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var studentID: String
    public var fromLevelRaw: String
    public var toLevelRaw: String
    public var statusRaw: String
    public var targetDate: Date?
    public var notes: String
}

public struct TransitionChecklistItemDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var transitionPlanID: String
    public var title: String
    public var categoryRaw: String
    public var isCompleted: Bool
    public var completedAt: Date?
    public var sortOrder: Int
    public var notes: String
}

// MARK: - Calendar CDNote DTO (format v12+)

public struct CalendarNoteDTO: Codable, Sendable {
    public var id: UUID
    public var year: Int
    public var month: Int
    public var day: Int
    public var text: String
    public var createdAt: Date
    public var modifiedAt: Date
}

// MARK: - Scheduled Meeting DTO (format v12+)

public struct ScheduledMeetingDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var date: Date
    public var createdAt: Date
}

// MARK: - Album Group DTOs (format v12+)

public struct AlbumGroupOrderDTO: Codable, Sendable {
    public var id: UUID
    public var scopeKey: String
    public var groupName: String
    public var sortIndex: Int
}

public struct AlbumGroupUIStateDTO: Codable, Sendable {
    public var id: UUID
    public var scopeKey: String
    public var groupName: String
    public var isCollapsed: Bool
}

// MARK: - Classroom Membership DTO (format v13+)

public struct ClassroomMembershipDTO: Codable, Sendable {
    public var id: UUID
    public var classroomZoneID: String
    public var roleRaw: String
    public var ownerIdentity: String
    public var joinedAt: Date
    public var modifiedAt: Date
}
