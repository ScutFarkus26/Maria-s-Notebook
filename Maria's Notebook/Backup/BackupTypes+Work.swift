import Foundation

// MARK: - Work DTOs

public struct WorkParticipantDTO: Codable, Sendable {
    public var studentID: UUID
    public var completedAt: Date?
}

/// Legacy DTO — retained for backward compatibility with older backup files.
public struct WorkDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var studentIDs: [UUID]
    public var workType: String
    public var assignmentUUID: UUID?
    public var createdAt: Date
    public var completedAt: Date?
    public var participants: [WorkParticipantDTO]
}

/// Modern DTO that captures all CDWorkModel fields (format v11+).
public struct WorkModelDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var workTypeRaw: String
    public var studentLessonID: UUID?
    public var createdAt: Date
    public var completedAt: Date?
    // Modern work tracking
    public var kindRaw: String?
    public var statusRaw: String
    public var assignedAt: Date
    public var lastTouchedAt: Date?
    public var dueAt: Date?
    public var completionOutcomeRaw: String?
    public var legacyContractID: UUID?
    // CloudKit-compatible string FKs
    public var studentID: String
    public var lessonID: String
    public var presentationID: String?
    public var trackID: String?
    public var trackStepID: String?
    public var scheduledNote: String?
    public var scheduledReasonRaw: String?
    public var sourceContextTypeRaw: String?
    public var sourceContextID: String?
    public var sampleWorkID: String?
    public var legacyStudentLessonID: String?
    public var checkInStyleRaw: String?
}

// MARK: - PlanningRecommendation DTO

public struct PlanningRecommendationDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var lessonID: String
    public var studentIDsData: Data?
    public var reasoning: String
    public var confidence: Double
    public var priority: Int
    public var subjectContext: String
    public var groupContext: String
    public var planningSessionID: String
    public var depthLevel: String
    public var decisionRaw: String?
    public var decisionAt: Date?
    public var teacherNote: String?
    public var outcomeRaw: String?
    public var outcomeRecordedAt: Date?
    public var presentationID: String?
}

// MARK: - CDResource DTO

public struct ResourceDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var descriptionText: String
    public var categoryRaw: String
    public var fileRelativePath: String
    public var fileSizeBytes: Int64
    public var tags: [String]
    public var isFavorite: Bool
    public var lastViewedAt: Date?
    public var linkedLessonIDs: String
    public var linkedSubjects: String
    public var createdAt: Date
    public var modifiedAt: Date
    // CDNote: fileBookmark and thumbnailData are @externalStorage and excluded from backups by design
}

// MARK: - CDNoteStudentLink DTO

public struct NoteStudentLinkDTO: Codable, Sendable {
    public var id: UUID
    public var noteID: String
    public var studentID: String
}

public struct WorkCheckInDTO: Codable, Sendable {
    public var id: UUID
    public var workID: String
    public var date: Date
    public var statusRaw: String
    public var purpose: String
}

public struct WorkStepDTO: Codable, Sendable {
    public var id: UUID
    public var workID: UUID?
    public var orderIndex: Int
    public var title: String
    public var instructions: String
    public var completedAt: Date?
    public var notes: String
    public var completionOutcomeRaw: String?
    public var createdAt: Date
}

public struct WorkParticipantEntityDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var completedAt: Date?
    public var workID: UUID?
}

public struct PracticeSessionDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var date: Date
    public var duration: TimeInterval?
    public var studentIDs: [String]
    public var workItemIDs: [String]
    public var sharedNotes: String
    public var location: String?
    public var practiceQuality: Int?
    public var independenceLevel: Int?
    public var askedForHelp: Bool
    public var helpedPeer: Bool
    public var struggledWithConcept: Bool
    public var madeBreakthrough: Bool
    public var needsReteaching: Bool
    public var readyForCheckIn: Bool
    public var readyForAssessment: Bool
    public var checkInScheduledFor: Date?
    public var followUpActions: String
    public var materialsUsed: String
    public var workStepID: String?
}

public struct WorkCompletionRecordDTO: Codable, Sendable {
    public var id: UUID
    public var workID: UUID
    public var studentID: UUID
    public var completedAt: Date
}

public struct AttendanceRecordDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: UUID
    public var date: Date
    public var status: String
    public var absenceReason: String?

    public init(id: UUID, studentID: UUID, date: Date, status: String, absenceReason: String? = nil) {
        self.id = id
        self.studentID = studentID
        self.date = date
        self.status = status
        self.absenceReason = absenceReason
    }
}
