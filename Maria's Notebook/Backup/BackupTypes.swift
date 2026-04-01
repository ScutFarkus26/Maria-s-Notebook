import Foundation

// MARK: - Constants
public enum BackupFile: Sendable {
    /// Marked as nonisolated to allow access from Sendable contexts (e.g., FileDocument static properties)
    nonisolated public static let fileExtension = "mtbbackup"
    /// Format version 13: Adds CDClassroomMembership backup coverage
    /// Format version 12: Adds CDGoingOut, CDClassroomJob, CDTransitionPlan, CDCalendarNote,
    /// CDScheduledMeeting, AlbumGroupOrder, AlbumGroupUIState backup coverage
    /// Format version 11: Adds CDWorkModel/CDPlanningRecommendation/CDResource/CDNoteStudentLink;
    /// removes LegacyPresentation backward compatibility
    /// Format version 10: Adds CDSampleWork/CDSampleWorkStep, CDWorkStep completionOutcome, CDPracticeSession workStepID
    /// Format version 8: Adds backup coverage for all entity types (Work, CDTrackEntity, CDSupply, Todo, etc.)
    /// Format version 7: Removes legacy WorkPlanItem backup compatibility
    /// Format version 6: Adds compression support (LZFSE)
    /// Format version 5: Enforces checksum validation with deterministic JSON encoding (.sortedKeys)
    nonisolated public static let formatVersion = 13
    /// Minimum format version that enforces checksum validation
    nonisolated public static let checksumEnforcedVersion = 5
    /// Format version that introduced compression (backups < this version are uncompressed)
    nonisolated public static let compressionIntroducedVersion = 6
    /// Compression algorithm constant
    nonisolated public static let compressionAlgorithm = "lzfse"
}

// MARK: - Envelope / Manifest / Payload
public struct BackupEnvelope: Codable, Sendable {
    public var formatVersion: Int
    public var createdAt: Date
    public var appBuild: String
    public var appVersion: String
    public var device: String
    public var manifest: BackupManifest
    // If encryption is enabled, payload is nil and encryptedPayload contains the encrypted bytes.
    // For format version 6+, compressedPayload may contain compressed (but not encrypted) data.
    public var payload: BackupPayload?
    public var encryptedPayload: Data?
    public var compressedPayload: Data?  // Format version 6+: compressed but unencrypted data

    enum CodingKeys: String, CodingKey {
        case formatVersion
        case createdAt
        case appBuild
        case appVersion
        case device
        case manifest
        case payload
        case encryptedPayload
        case compressedPayload
    }

    public init(
        formatVersion: Int, createdAt: Date,
        appBuild: String, appVersion: String, device: String,
        manifest: BackupManifest,
        payload: BackupPayload? = nil,
        encryptedPayload: Data? = nil,
        compressedPayload: Data? = nil
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.appBuild = appBuild
        self.appVersion = appVersion
        self.device = device
        self.manifest = manifest
        self.payload = payload
        self.encryptedPayload = encryptedPayload
        self.compressedPayload = compressedPayload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.appBuild = try container.decode(String.self, forKey: .appBuild)
        self.appVersion = try container.decode(String.self, forKey: .appVersion)
        self.device = try container.decode(String.self, forKey: .device)
        self.manifest = try container.decode(BackupManifest.self, forKey: .manifest)
        self.payload = try container.decodeIfPresent(BackupPayload.self, forKey: .payload)
        self.encryptedPayload = try container.decodeIfPresent(Data.self, forKey: .encryptedPayload)
        self.compressedPayload = try container.decodeIfPresent(Data.self, forKey: .compressedPayload)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(appBuild, forKey: .appBuild)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(device, forKey: .device)
        try container.encode(manifest, forKey: .manifest)
        try container.encodeIfPresent(payload, forKey: .payload)
        try container.encodeIfPresent(encryptedPayload, forKey: .encryptedPayload)
        try container.encodeIfPresent(compressedPayload, forKey: .compressedPayload)
    }
}

public struct BackupManifest: Codable, Sendable {
    public var entityCounts: [String: Int]
    public var sha256: String
    public var notes: String?
    /// Compression algorithm used (if any). nil means no compression (backward compatible)
    public var compression: String?

    public init(entityCounts: [String: Int], sha256: String, notes: String? = nil, compression: String? = nil) {
        self.entityCounts = entityCounts
        self.sha256 = sha256
        self.notes = notes
        self.compression = compression
    }
}

// MARK: - PreferencesDTO and PreferenceValueDTO
public struct PreferencesDTO: Codable, Sendable {
    public var values: [String: PreferenceValueDTO]
}

public enum PreferenceValueDTO: Codable, Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case date(Date)

    enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    enum ValueType: String, Codable {
        case bool
        case int
        case double
        case string
        case data
        case date
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .int:
            self = .int(try container.decode(Int.self, forKey: .value))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .value))
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .data:
            self = .data(try container.decode(Data.self, forKey: .value))
        case .date:
            self = .date(try container.decode(Date.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let b):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(b, forKey: .value)
        case .int(let i):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(i, forKey: .value)
        case .double(let d):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(d, forKey: .value)
        case .string(let s):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(s, forKey: .value)
        case .data(let data):
            try container.encode(ValueType.data, forKey: .type)
            try container.encode(data, forKey: .value)
        case .date(let date):
            try container.encode(ValueType.date, forKey: .type)
            try container.encode(date, forKey: .value)
        }
    }
}

// MARK: - BackupPayload
public struct BackupPayload: Codable, Sendable {

    enum CodingKeys: String, CodingKey {
        case items, students, lessons
        case lessonAssignments, notes, nonSchoolDays, schoolDayOverrides
        case studentMeetings, communityTopics, proposedSolutions, communityAttachments
        case attendance, workCompletions
        case projects, projectAssignmentTemplates, projectSessions, projectRoles
        case projectTemplateWeeks, projectWeekRoleAssignments
        case workModels
        case workCheckIns, workSteps, workParticipants, practiceSessions
        case lessonAttachments, lessonPresentations
        case sampleWorks, sampleWorkSteps
        case noteTemplates, meetingTemplates
        case reminders, calendarEvents
        case tracks, trackSteps, studentTrackEnrollments, groupTracks
        case documents
        case supplies, supplyTransactions, procedures
        case schedules, scheduleSlots
        case issues, issueActions
        case developmentSnapshots
        case todoItems, todoSubtasks, todoTemplates
        case todayAgendaOrders
        case planningRecommendations, resources, noteStudentLinks
        case goingOuts, goingOutChecklistItems
        case classroomJobs, jobAssignments
        case transitionPlans, transitionChecklistItems
        case calendarNotes, scheduledMeetings
        case albumGroupOrders, albumGroupUIStates
        case classroomMemberships
        case preferences
    }

    // Arrays for each entity type as DTOs (IDs only for relationships; exclude file bytes)
    public var items: [ItemDTO]
    public var students: [StudentDTO]
    public var lessons: [LessonDTO]
    public var lessonAssignments: [LessonAssignmentDTO]
    public var notes: [NoteDTO]
    public var nonSchoolDays: [NonSchoolDayDTO]
    public var schoolDayOverrides: [SchoolDayOverrideDTO]
    public var studentMeetings: [StudentMeetingDTO]
    public var communityTopics: [CommunityTopicDTO]
    public var proposedSolutions: [ProposedSolutionDTO]
    public var communityAttachments: [CommunityAttachmentDTO]

    // Attendance and Work Completions
    public var attendance: [AttendanceRecordDTO]
    public var workCompletions: [WorkCompletionRecordDTO]

    // CDProject entities
    public var projects: [ProjectDTO]
    public var projectAssignmentTemplates: [ProjectAssignmentTemplateDTO]
    public var projectSessions: [ProjectSessionDTO]
    public var projectRoles: [ProjectRoleDTO]
    public var projectTemplateWeeks: [ProjectTemplateWeekDTO]
    public var projectWeekRoleAssignments: [ProjectWeekRoleAssignmentDTO]

    // Work models (format v11+) — the parent entity for work tracking
    public var workModels: [WorkModelDTO]?

    // Work tracking (format v8+)
    public var workCheckIns: [WorkCheckInDTO]?
    public var workSteps: [WorkStepDTO]?
    public var workParticipants: [WorkParticipantEntityDTO]?
    public var practiceSessions: [PracticeSessionDTO]?

    // CDLesson extras (format v8+)
    public var lessonAttachments: [LessonAttachmentDTO]?
    public var lessonPresentations: [LessonPresentationDTO]?
    // Sample works (format v10+)
    public var sampleWorks: [SampleWorkDTO]?
    public var sampleWorkSteps: [SampleWorkStepDTO]?

    // Templates (format v8+)
    public var noteTemplates: [NoteTemplateDTO]?
    public var meetingTemplates: [MeetingTemplateDTO]?

    // Reminders & Calendar (format v8+)
    public var reminders: [ReminderDTO]?
    public var calendarEvents: [CalendarEventDTO]?

    // Tracks (format v8+)
    public var tracks: [TrackDTO]?
    public var trackSteps: [TrackStepDTO]?
    public var studentTrackEnrollments: [StudentTrackEnrollmentDTO]?
    public var groupTracks: [GroupTrackDTO]?

    // Documents metadata (format v8+)
    public var documents: [DocumentDTO]?

    // Supplies & Procedures (format v8+)
    public var supplies: [SupplyDTO]?
    public var supplyTransactions: [SupplyTransactionDTO]?
    public var procedures: [ProcedureDTO]?

    // Schedules (format v8+)
    public var schedules: [ScheduleDTO]?
    public var scheduleSlots: [ScheduleSlotDTO]?

    // Issues (format v8+)
    public var issues: [IssueDTO]?
    public var issueActions: [IssueActionDTO]?

    // Development (format v8+)
    public var developmentSnapshots: [DevelopmentSnapshotDTO]?

    // Todos (format v8+)
    public var todoItems: [TodoItemDTO]?
    public var todoSubtasks: [TodoSubtaskDTO]?
    public var todoTemplates: [TodoTemplateDTO]?

    // Agenda ordering (format v8+)
    public var todayAgendaOrders: [TodayAgendaOrderDTO]?

    // Planning recommendations (format v11+)
    public var planningRecommendations: [PlanningRecommendationDTO]?

    // Resources (format v11+)
    public var resources: [ResourceDTO]?

    // CDNote-CDStudent junction links (format v11+)
    public var noteStudentLinks: [NoteStudentLinkDTO]?

    // Going Out (format v12+)
    public var goingOuts: [GoingOutDTO]?
    public var goingOutChecklistItems: [GoingOutChecklistItemDTO]?

    // Classroom Jobs (format v12+)
    public var classroomJobs: [ClassroomJobDTO]?
    public var jobAssignments: [JobAssignmentDTO]?

    // Transition Plans (format v12+)
    public var transitionPlans: [TransitionPlanDTO]?
    public var transitionChecklistItems: [TransitionChecklistItemDTO]?

    // Calendar Notes (format v12+)
    public var calendarNotes: [CalendarNoteDTO]?

    // Scheduled Meetings (format v12+)
    public var scheduledMeetings: [ScheduledMeetingDTO]?

    // Album Group state (format v12+)
    public var albumGroupOrders: [AlbumGroupOrderDTO]?
    public var albumGroupUIStates: [AlbumGroupUIStateDTO]?

    // Classroom Membership (format v13+)
    public var classroomMemberships: [ClassroomMembershipDTO]?

    // Lightweight app/user metadata (preferences) as typed dictionary
    public var preferences: PreferencesDTO
}

// MARK: - UI Summary Helper
public struct BackupSummary: Codable, Hashable, Sendable {
    public var totalCount: Int
    public var countsByEntity: [String: Int]
}

// MARK: - BackupOperationSummary
public struct BackupOperationSummary: Identifiable, Sendable {
    public enum Kind: Sendable, Equatable {
        case export
        case `import`
    }

    public let id = UUID()
    public let kind: Kind
    public let fileName: String
    public let formatVersion: Int
    public let encryptUsed: Bool
    public let createdAt: Date
    public let entityCounts: [String: Int]
    public let warnings: [String]
}

// MARK: - RestorePreview (for Restore Preview UI)
public struct RestorePreview: Codable, Sendable, Equatable {
    public var mode: String
    public var entityInserts: [String: Int]
    public var entitySkips: [String: Int]
    public var entityDeletes: [String: Int]
    public var totalInserts: Int
    public var totalDeletes: Int
    public var warnings: [String]
    public init(
        mode: String,
        entityInserts: [String: Int], entitySkips: [String: Int],
        entityDeletes: [String: Int],
        totalInserts: Int, totalDeletes: Int,
        warnings: [String]
    ) {
        self.mode = mode
        self.entityInserts = entityInserts
        self.entitySkips = entitySkips
        self.entityDeletes = entityDeletes
        self.totalInserts = totalInserts
        self.totalDeletes = totalDeletes
        self.warnings = warnings
    }
}
