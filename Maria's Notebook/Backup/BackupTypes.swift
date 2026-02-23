import Foundation

// MARK: - Constants
public enum BackupFile: Sendable {
    /// Marked as nonisolated to allow access from Sendable contexts (e.g., FileDocument static properties)
    nonisolated public static let fileExtension = "mtbbackup"
    /// Format version 7: Removes legacy WorkPlanItem backup compatibility
    /// Format version 6: Adds compression support (LZFSE)
    /// Format version 5: Enforces checksum validation with deterministic JSON encoding (.sortedKeys)
    nonisolated public static let formatVersion = 7
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
    public var payload: BackupPayload? = nil
    public var encryptedPayload: Data? = nil
    public var compressedPayload: Data? = nil  // Format version 6+: compressed but unencrypted data

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

    public init(formatVersion: Int, createdAt: Date, appBuild: String, appVersion: String, device: String, manifest: BackupManifest, payload: BackupPayload? = nil, encryptedPayload: Data? = nil, compressedPayload: Data? = nil) {
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
    public var compression: String? = nil
    
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
    // Arrays for each entity type as DTOs (IDs only for relationships; exclude file bytes)
    public var items: [ItemDTO]
    public var students: [StudentDTO]
    public var lessons: [LessonDTO]
    public var studentLessons: [StudentLessonDTO]
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

    // Project entities
    public var projects: [ProjectDTO]
    public var projectAssignmentTemplates: [ProjectAssignmentTemplateDTO]
    public var projectSessions: [ProjectSessionDTO]
    public var projectRoles: [ProjectRoleDTO]
    public var projectTemplateWeeks: [ProjectTemplateWeekDTO]
    public var projectWeekRoleAssignments: [ProjectWeekRoleAssignmentDTO]

    // Lightweight app/user metadata (preferences) as typed dictionary
    public var preferences: PreferencesDTO

    public init(
        items: [ItemDTO],
        students: [StudentDTO],
        lessons: [LessonDTO],
        studentLessons: [StudentLessonDTO],
        lessonAssignments: [LessonAssignmentDTO],
        notes: [NoteDTO],
        nonSchoolDays: [NonSchoolDayDTO],
        schoolDayOverrides: [SchoolDayOverrideDTO],
        studentMeetings: [StudentMeetingDTO],
        communityTopics: [CommunityTopicDTO],
        proposedSolutions: [ProposedSolutionDTO],
        communityAttachments: [CommunityAttachmentDTO],
        attendance: [AttendanceRecordDTO],
        workCompletions: [WorkCompletionRecordDTO],
        projects: [ProjectDTO],
        projectAssignmentTemplates: [ProjectAssignmentTemplateDTO],
        projectSessions: [ProjectSessionDTO],
        projectRoles: [ProjectRoleDTO],
        projectTemplateWeeks: [ProjectTemplateWeekDTO],
        projectWeekRoleAssignments: [ProjectWeekRoleAssignmentDTO],
        preferences: PreferencesDTO
    ) {
        self.items = items
        self.students = students
        self.lessons = lessons
        self.studentLessons = studentLessons
        self.lessonAssignments = lessonAssignments
        self.notes = notes
        self.nonSchoolDays = nonSchoolDays
        self.schoolDayOverrides = schoolDayOverrides
        self.studentMeetings = studentMeetings
        self.communityTopics = communityTopics
        self.proposedSolutions = proposedSolutions
        self.communityAttachments = communityAttachments
        self.attendance = attendance
        self.workCompletions = workCompletions
        self.projects = projects
        self.projectAssignmentTemplates = projectAssignmentTemplates
        self.projectSessions = projectSessions
        self.projectRoles = projectRoles
        self.projectTemplateWeeks = projectTemplateWeeks
        self.projectWeekRoleAssignments = projectWeekRoleAssignments
        self.preferences = preferences
    }
}

// MARK: - DTOs (IDs and fields only; exclude file data)
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
}

public struct StudentLessonDTO: Codable, Sendable {
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

public struct WorkParticipantDTO: Codable, Sendable {
    public var studentID: UUID
    public var completedAt: Date?
}

public struct WorkDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var studentIDs: [UUID]
    public var workType: String
    public var studentLessonID: UUID?
    public var notes: String
    public var createdAt: Date
    public var completedAt: Date?
    public var participants: [WorkParticipantDTO]
}

public struct AttendanceRecordDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: UUID
    public var date: Date
    public var status: String
    public var absenceReason: String?
    public var note: String?
    
    public init(id: UUID, studentID: UUID, date: Date, status: String, absenceReason: String? = nil, note: String? = nil) {
        self.id = id
        self.studentID = studentID
        self.date = date
        self.status = status
        self.absenceReason = absenceReason
        self.note = note
    }
}

public struct WorkCompletionRecordDTO: Codable, Sendable {
    public var id: UUID
    public var workID: UUID
    public var studentID: UUID
    public var completedAt: Date
    public var note: String
}


public struct NoteDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var body: String
    public var isPinned: Bool
    public var scope: String // serialized enum value
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
    public var note: String?
}

public struct StudentMeetingDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: UUID
    public var date: Date
    public var completed: Bool
    public var reflection: String
    public var focus: String
    public var requests: String
    public var guideNotes: String
}

// MARK: - LessonAssignment DTO
/// DTO for the unified LessonAssignment model.
/// This model replaces StudentLesson + Presentation in the new architecture.
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
    public var migratedFromStudentLessonID: String?
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
        migratedFromStudentLessonID: String?,
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
        self.migratedFromStudentLessonID = migratedFromStudentLessonID
        self.migratedFromPresentationID = migratedFromPresentationID
    }
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

// MARK: - Project DTOs
public struct ProjectDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var bookTitle: String?
    public var memberStudentIDs: [String]
}

public struct ProjectAssignmentTemplateDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var title: String
    public var instructions: String
    public var isShared: Bool
    public var defaultLinkedLessonID: String?
}

public struct ProjectSessionDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var meetingDate: Date
    public var chapterOrPages: String?
    public var notes: String?
    public var agendaItemsJSON: String
    public var templateWeekID: UUID?
}

public struct ProjectRoleDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var title: String
    public var summary: String
    public var instructions: String
}

public struct ProjectTemplateWeekDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var weekIndex: Int
    public var readingRange: String
    public var agendaItemsJSON: String
    public var linkedLessonIDsJSON: String
    public var workInstructions: String
}

public struct ProjectWeekRoleAssignmentDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var weekID: UUID
    public var studentID: String
    public var roleID: UUID
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
    public init(mode: String, entityInserts: [String: Int], entitySkips: [String: Int], entityDeletes: [String: Int], totalInserts: Int, totalDeletes: Int, warnings: [String]) {
        self.mode = mode
        self.entityInserts = entityInserts
        self.entitySkips = entitySkips
        self.entityDeletes = entityDeletes
        self.totalInserts = totalInserts
        self.totalDeletes = totalDeletes
        self.warnings = warnings
    }
}
