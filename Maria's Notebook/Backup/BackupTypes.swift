import Foundation

// MARK: - Constants
public enum BackupFile {
    public static let fileExtension = "mtbbackup"
    /// Format version 6: Adds compression support (LZFSE) while maintaining backward compatibility
    /// Format version 5: Enforces checksum validation with deterministic JSON encoding (.sortedKeys)
    public static let formatVersion = 6
    /// Minimum format version that enforces checksum validation
    public static let checksumEnforcedVersion = 5
    /// Format version that introduced compression (backups < this version are uncompressed)
    public static let compressionIntroducedVersion = 6
    /// Compression algorithm constant
    public static let compressionAlgorithm = "lzfse"
}

// MARK: - Envelope / Manifest / Payload
public struct BackupEnvelope: Codable {
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

public struct BackupManifest: Codable {
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
        // Try keyed container first
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            let type = try container.decode(ValueType.self, forKey: .type)
            switch type {
            case .bool:
                let v = try container.decode(Bool.self, forKey: .value)
                self = .bool(v)
            case .int:
                let v = try container.decode(Int.self, forKey: .value)
                self = .int(v)
            case .double:
                let v = try container.decode(Double.self, forKey: .value)
                self = .double(v)
            case .string:
                let v = try container.decode(String.self, forKey: .value)
                self = .string(v)
            case .data:
                let v = try container.decode(Data.self, forKey: .value)
                self = .data(v)
            case .date:
                let v = try container.decode(Date.self, forKey: .value)
                self = .date(v)
            }
        } else {
            // Fallback for backward compatibility to legacy string
            let singleContainer = try decoder.singleValueContainer()
            let legacyValue = try singleContainer.decode(String.self)
            self = .string(legacyValue)
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
public struct BackupPayload: Codable {
    // Arrays for each entity type as DTOs (IDs only for relationships; exclude file bytes)
    public var items: [ItemDTO]
    public var students: [StudentDTO]
    public var lessons: [LessonDTO]
    public var studentLessons: [StudentLessonDTO]
    public var workContracts: [WorkContractDTO]
    public var workPlanItems: [WorkPlanItemDTO]
    public var scopedNotes: [ScopedNoteDTO]
    public var notes: [NoteDTO]
    public var nonSchoolDays: [NonSchoolDayDTO]
    public var schoolDayOverrides: [SchoolDayOverrideDTO]
    public var studentMeetings: [StudentMeetingDTO]
    public var presentations: [PresentationDTO]
    public var communityTopics: [CommunityTopicDTO]
    public var proposedSolutions: [ProposedSolutionDTO]
    public var meetingNotes: [MeetingNoteDTO]
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

    enum CodingKeys: String, CodingKey {
        case items
        case students
        case lessons
        case studentLessons
        case workContracts
        case workPlanItems
        case scopedNotes
        case notes
        case nonSchoolDays
        case schoolDayOverrides
        case studentMeetings
        case presentations
        case communityTopics
        case proposedSolutions
        case meetingNotes
        case communityAttachments
        case attendance
        case workCompletions
        case projects
        case projectAssignmentTemplates
        case projectSessions
        case projectRoles
        case projectTemplateWeeks
        case projectWeekRoleAssignments
        // Backward compatibility: old bookClub keys
        case bookClubs
        case bookClubAssignmentTemplates
        case bookClubSessions
        case bookClubRoles
        case bookClubTemplateWeeks
        case bookClubWeekRoleAssignments
        // Removed bookClubChoiceSets and bookClubChoiceItems
        case preferences
    }

    public init(
        items: [ItemDTO],
        students: [StudentDTO],
        lessons: [LessonDTO],
        studentLessons: [StudentLessonDTO],
        workContracts: [WorkContractDTO],
        workPlanItems: [WorkPlanItemDTO],
        scopedNotes: [ScopedNoteDTO],
        notes: [NoteDTO],
        nonSchoolDays: [NonSchoolDayDTO],
        schoolDayOverrides: [SchoolDayOverrideDTO],
        studentMeetings: [StudentMeetingDTO],
        presentations: [PresentationDTO],
        communityTopics: [CommunityTopicDTO],
        proposedSolutions: [ProposedSolutionDTO],
        meetingNotes: [MeetingNoteDTO],
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
        self.workContracts = workContracts
        self.workPlanItems = workPlanItems
        self.scopedNotes = scopedNotes
        self.notes = notes
        self.nonSchoolDays = nonSchoolDays
        self.schoolDayOverrides = schoolDayOverrides
        self.studentMeetings = studentMeetings
        self.presentations = presentations
        self.communityTopics = communityTopics
        self.proposedSolutions = proposedSolutions
        self.meetingNotes = meetingNotes
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decode([ItemDTO].self, forKey: .items)
        self.students = try container.decode([StudentDTO].self, forKey: .students)
        self.lessons = try container.decode([LessonDTO].self, forKey: .lessons)
        self.studentLessons = try container.decode([StudentLessonDTO].self, forKey: .studentLessons)
        self.workContracts = try container.decode([WorkContractDTO].self, forKey: .workContracts)
        self.workPlanItems = try container.decode([WorkPlanItemDTO].self, forKey: .workPlanItems)
        self.scopedNotes = try container.decode([ScopedNoteDTO].self, forKey: .scopedNotes)
        self.notes = try container.decode([NoteDTO].self, forKey: .notes)
        self.nonSchoolDays = try container.decode([NonSchoolDayDTO].self, forKey: .nonSchoolDays)
        self.schoolDayOverrides = try container.decode([SchoolDayOverrideDTO].self, forKey: .schoolDayOverrides)
        self.studentMeetings = try container.decode([StudentMeetingDTO].self, forKey: .studentMeetings)
        self.presentations = try container.decode([PresentationDTO].self, forKey: .presentations)
        self.communityTopics = try container.decode([CommunityTopicDTO].self, forKey: .communityTopics)
        self.proposedSolutions = try container.decode([ProposedSolutionDTO].self, forKey: .proposedSolutions)
        self.meetingNotes = try container.decode([MeetingNoteDTO].self, forKey: .meetingNotes)
        self.communityAttachments = try container.decode([CommunityAttachmentDTO].self, forKey: .communityAttachments)

        // New arrays (backward compatible)
        self.attendance = try container.decodeIfPresent([AttendanceRecordDTO].self, forKey: .attendance) ?? []
        self.workCompletions = try container.decodeIfPresent([WorkCompletionRecordDTO].self, forKey: .workCompletions) ?? []
        
        // Projects: Try new keys first, then fall back to old keys for backward compatibility
        if let newProjects = try container.decodeIfPresent([ProjectDTO].self, forKey: .projects) {
            self.projects = newProjects
        } else if let oldBookClubs = try container.decodeIfPresent([BookClubDTO].self, forKey: .bookClubs) {
            // Convert old BookClubDTO to new ProjectDTO
            self.projects = oldBookClubs.map { BookClubDTO.toProjectDTO($0) }
        } else {
            self.projects = []
        }
        
        if let newTemplates = try container.decodeIfPresent([ProjectAssignmentTemplateDTO].self, forKey: .projectAssignmentTemplates) {
            self.projectAssignmentTemplates = newTemplates
        } else if let oldTemplates = try container.decodeIfPresent([BookClubAssignmentTemplateDTO].self, forKey: .bookClubAssignmentTemplates) {
            self.projectAssignmentTemplates = oldTemplates.map { BookClubAssignmentTemplateDTO.toProjectDTO($0) }
        } else {
            self.projectAssignmentTemplates = []
        }
        
        if let newSessions = try container.decodeIfPresent([ProjectSessionDTO].self, forKey: .projectSessions) {
            self.projectSessions = newSessions
        } else if let oldSessions = try container.decodeIfPresent([BookClubSessionDTO].self, forKey: .bookClubSessions) {
            self.projectSessions = oldSessions.map { BookClubSessionDTO.toProjectDTO($0) }
        } else {
            self.projectSessions = []
        }
        
        if let newRoles = try container.decodeIfPresent([ProjectRoleDTO].self, forKey: .projectRoles) {
            self.projectRoles = newRoles
        } else if let oldRoles = try container.decodeIfPresent([BookClubRoleDTO].self, forKey: .bookClubRoles) {
            self.projectRoles = oldRoles.map { BookClubRoleDTO.toProjectDTO($0) }
        } else {
            self.projectRoles = []
        }
        
        if let newWeeks = try container.decodeIfPresent([ProjectTemplateWeekDTO].self, forKey: .projectTemplateWeeks) {
            self.projectTemplateWeeks = newWeeks
        } else if let oldWeeks = try container.decodeIfPresent([BookClubTemplateWeekDTO].self, forKey: .bookClubTemplateWeeks) {
            self.projectTemplateWeeks = oldWeeks.map { BookClubTemplateWeekDTO.toProjectDTO($0) }
        } else {
            self.projectTemplateWeeks = []
        }
        
        if let newAssignments = try container.decodeIfPresent([ProjectWeekRoleAssignmentDTO].self, forKey: .projectWeekRoleAssignments) {
            self.projectWeekRoleAssignments = newAssignments
        } else if let oldAssignments = try container.decodeIfPresent([BookClubWeekRoleAssignmentDTO].self, forKey: .bookClubWeekRoleAssignments) {
            self.projectWeekRoleAssignments = oldAssignments.map { BookClubWeekRoleAssignmentDTO.toProjectDTO($0) }
        } else {
            self.projectWeekRoleAssignments = []
        }

        self.preferences = try container.decode(PreferencesDTO.self, forKey: .preferences)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encode(students, forKey: .students)
        try container.encode(lessons, forKey: .lessons)
        try container.encode(studentLessons, forKey: .studentLessons)
        try container.encode(workContracts, forKey: .workContracts)
        try container.encode(workPlanItems, forKey: .workPlanItems)
        try container.encode(scopedNotes, forKey: .scopedNotes)
        try container.encode(notes, forKey: .notes)
        try container.encode(nonSchoolDays, forKey: .nonSchoolDays)
        try container.encode(schoolDayOverrides, forKey: .schoolDayOverrides)
        try container.encode(studentMeetings, forKey: .studentMeetings)
        try container.encode(presentations, forKey: .presentations)
        try container.encode(communityTopics, forKey: .communityTopics)
        try container.encode(proposedSolutions, forKey: .proposedSolutions)
        try container.encode(meetingNotes, forKey: .meetingNotes)
        try container.encode(communityAttachments, forKey: .communityAttachments)
        try container.encode(attendance, forKey: .attendance)
        try container.encode(workCompletions, forKey: .workCompletions)
        try container.encode(projects, forKey: .projects)
        try container.encode(projectAssignmentTemplates, forKey: .projectAssignmentTemplates)
        try container.encode(projectSessions, forKey: .projectSessions)
        try container.encode(projectRoles, forKey: .projectRoles)
        try container.encode(projectTemplateWeeks, forKey: .projectTemplateWeeks)
        try container.encode(projectWeekRoleAssignments, forKey: .projectWeekRoleAssignments)
        try container.encode(preferences, forKey: .preferences)
    }
}

// MARK: - DTOs (IDs and fields only; exclude file data)
public struct ItemDTO: Codable {
    public var id: UUID
    public var timestamp: Date
}

public struct StudentDTO: Codable {
    public enum Level: String, Codable { case lower, upper }
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

public struct LessonDTO: Codable {
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

public struct StudentLessonDTO: Codable {
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

public struct WorkParticipantDTO: Codable {
    public var studentID: UUID
    public var completedAt: Date?
}

public struct WorkDTO: Codable {
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

public struct AttendanceRecordDTO: Codable {
    public var id: UUID
    public var studentID: UUID
    public var date: Date
    public var status: String
    public var note: String?
}

public struct WorkCompletionRecordDTO: Codable {
    public var id: UUID
    public var workID: UUID
    public var studentID: UUID
    public var completedAt: Date
    public var note: String
}

public struct WorkContractDTO: Codable {
    public var id: UUID
    public var studentID: String
    public var lessonID: String
    public var presentationID: String?
    public var status: String
    public var scheduledDate: Date?
    public var createdAt: Date?
    public var completedAt: Date?
    public var kind: String?
    public var scheduledReason: String?
    public var scheduledNote: String?
    public var completionOutcome: String?
    public var completionNote: String?
    public var legacyStudentLessonID: String?
}

public struct WorkPlanItemDTO: Codable {
    public var id: UUID
    public var workID: UUID
    public var scheduledDate: Date
    public var reason: String
    public var note: String?
}

public struct ScopedNoteDTO: Codable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var body: String
    public var scope: String // serialized enum value
    public var legacyFingerprint: String?
    public var studentLessonID: UUID?
    public var workID: UUID?
    public var presentationID: UUID?
    public var workContractID: UUID?
}

public struct NoteDTO: Codable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var body: String
    public var isPinned: Bool
    public var scope: String // serialized enum value
    public var lessonID: UUID?
    public var workID: UUID?
}

public struct NonSchoolDayDTO: Codable {
    public var id: UUID
    public var date: Date
    public var reason: String?
}

public struct SchoolDayOverrideDTO: Codable {
    public var id: UUID
    public var date: Date
    public var note: String?
}

public struct StudentMeetingDTO: Codable {
    public var id: UUID
    public var studentID: UUID
    public var date: Date
    public var completed: Bool
    public var reflection: String
    public var focus: String
    public var requests: String
    public var guideNotes: String
}

public struct PresentationDTO: Codable {
    public var id: UUID
    public var createdAt: Date
    public var presentedAt: Date
    public var lessonID: String
    public var studentIDs: [String]
    public var legacyStudentLessonID: String?
    public var lessonTitleSnapshot: String?
    public var lessonSubtitleSnapshot: String?
}

public struct CommunityTopicDTO: Codable {
    public var id: UUID
    public var title: String
    public var issueDescription: String
    public var createdAt: Date
    public var addressedDate: Date?
    public var resolution: String
    public var raisedBy: String
    public var tags: [String]
}

public struct ProposedSolutionDTO: Codable {
    public var id: UUID
    public var topicID: UUID?
    public var title: String
    public var details: String
    public var proposedBy: String
    public var createdAt: Date
    public var isAdopted: Bool
}

public struct MeetingNoteDTO: Codable {
    public var id: UUID
    public var topicID: UUID?
    public var speaker: String
    public var content: String
    public var createdAt: Date
}

public struct CommunityAttachmentDTO: Codable {
    public var id: UUID
    public var topicID: UUID?
    public var filename: String
    public var kind: String
    // Do not include raw data; metadata only
    public var createdAt: Date
}

// MARK: - Project DTOs
public struct ProjectDTO: Codable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var bookTitle: String?
    public var memberStudentIDs: [String]
}

// MARK: - Legacy BookClub DTOs (for backward compatibility)
private struct BookClubDTO: Codable {
    var id: UUID
    var createdAt: Date
    var title: String
    var bookTitle: String?
    var memberStudentIDs: [String]
    
    static func toProjectDTO(_ old: BookClubDTO) -> ProjectDTO {
        ProjectDTO(id: old.id, createdAt: old.createdAt, title: old.title, bookTitle: old.bookTitle, memberStudentIDs: old.memberStudentIDs)
    }
}

private struct BookClubAssignmentTemplateDTO: Codable {
    var id: UUID
    var createdAt: Date
    var bookClubID: UUID
    var title: String
    var instructions: String
    var isShared: Bool
    var defaultLinkedLessonID: String?
    
    static func toProjectDTO(_ old: BookClubAssignmentTemplateDTO) -> ProjectAssignmentTemplateDTO {
        ProjectAssignmentTemplateDTO(id: old.id, createdAt: old.createdAt, projectID: old.bookClubID, title: old.title, instructions: old.instructions, isShared: old.isShared, defaultLinkedLessonID: old.defaultLinkedLessonID)
    }
}

private struct BookClubSessionDTO: Codable {
    var id: UUID
    var createdAt: Date
    var bookClubID: UUID
    var meetingDate: Date
    var chapterOrPages: String?
    var notes: String?
    var agendaItemsJSON: String
    var templateWeekID: UUID?
    
    static func toProjectDTO(_ old: BookClubSessionDTO) -> ProjectSessionDTO {
        ProjectSessionDTO(id: old.id, createdAt: old.createdAt, projectID: old.bookClubID, meetingDate: old.meetingDate, chapterOrPages: old.chapterOrPages, notes: old.notes, agendaItemsJSON: old.agendaItemsJSON, templateWeekID: old.templateWeekID)
    }
}

private struct BookClubRoleDTO: Codable {
    var id: UUID
    var createdAt: Date
    var bookClubID: UUID
    var title: String
    var summary: String
    var instructions: String
    
    static func toProjectDTO(_ old: BookClubRoleDTO) -> ProjectRoleDTO {
        ProjectRoleDTO(id: old.id, createdAt: old.createdAt, projectID: old.bookClubID, title: old.title, summary: old.summary, instructions: old.instructions)
    }
}

private struct BookClubTemplateWeekDTO: Codable {
    var id: UUID
    var createdAt: Date
    var bookClubID: UUID
    var weekIndex: Int
    var readingRange: String
    var agendaItemsJSON: String
    var linkedLessonIDsJSON: String
    var workInstructions: String
    
    static func toProjectDTO(_ old: BookClubTemplateWeekDTO) -> ProjectTemplateWeekDTO {
        ProjectTemplateWeekDTO(id: old.id, createdAt: old.createdAt, projectID: old.bookClubID, weekIndex: old.weekIndex, readingRange: old.readingRange, agendaItemsJSON: old.agendaItemsJSON, linkedLessonIDsJSON: old.linkedLessonIDsJSON, workInstructions: old.workInstructions)
    }
}

private struct BookClubWeekRoleAssignmentDTO: Codable {
    var id: UUID
    var createdAt: Date
    var weekID: UUID
    var studentID: String
    var roleID: UUID
    
    static func toProjectDTO(_ old: BookClubWeekRoleAssignmentDTO) -> ProjectWeekRoleAssignmentDTO {
        ProjectWeekRoleAssignmentDTO(id: old.id, createdAt: old.createdAt, weekID: old.weekID, studentID: old.studentID, roleID: old.roleID)
    }
}

public struct ProjectAssignmentTemplateDTO: Codable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var title: String
    public var instructions: String
    public var isShared: Bool
    public var defaultLinkedLessonID: String?
}

public struct ProjectSessionDTO: Codable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var meetingDate: Date
    public var chapterOrPages: String?
    public var notes: String?
    public var agendaItemsJSON: String
    public var templateWeekID: UUID?
}

public struct ProjectRoleDTO: Codable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var title: String
    public var summary: String
    public var instructions: String
}

public struct ProjectTemplateWeekDTO: Codable {
    public var id: UUID
    public var createdAt: Date
    public var projectID: UUID
    public var weekIndex: Int
    public var readingRange: String
    public var agendaItemsJSON: String
    public var linkedLessonIDsJSON: String
    public var workInstructions: String
}

public struct ProjectWeekRoleAssignmentDTO: Codable {
    public var id: UUID
    public var createdAt: Date
    public var weekID: UUID
    public var studentID: String
    public var roleID: UUID
}

// MARK: - UI Summary Helper
public struct BackupSummary: Codable, Hashable {
    public var totalCount: Int
    public var countsByEntity: [String: Int]
}
// MARK: - BackupOperationSummary
public struct BackupOperationSummary: Identifiable, Sendable {
    public enum Kind: Sendable {
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

