import Foundation
import SwiftData

// MARK: - Assignment Mode

/// Describes how work is assigned in a project session
public enum SessionAssignmentMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case uniform    // Everyone gets the same work (auto-assigned to all)
    case choice     // Teacher offers N works, students pick M

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .uniform: return "Uniform"
        case .choice: return "Student Choice"
        }
    }

    public var description: String {
        switch self {
        case .uniform: return "All students receive the same assignments"
        case .choice: return "Students choose from offered works"
        }
    }
}

// Local JSON helper to avoid cross-file dependency
struct LocalJSONStringList {
    nonisolated static func encode(_ arr: [String]) -> String {
        guard !arr.isEmpty else { return "" }
        if let data = try? JSONEncoder().encode(arr), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return ""
    }
    nonisolated static func decode(_ s: String) -> [String] {
        let trimmed = s.trimmed()
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        if let arr = try? JSONDecoder().decode([String].self, from: data) { return arr }
        return []
    }
}

// MARK: - Models

@Model
final class Project: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// Timestamp of when this record was last modified locally.
    /// Used for smarter CloudKit conflict resolution - prefer the most recently modified record.
    var modifiedAt: Date = Date()

    var title: String = ""
    var bookTitle: String? = nil

    // Store Student IDs as strings for CloudKit compatibility
    var memberStudentIDs: [String] = []

    var isActive: Bool = true

    // Relationships - FIX: Made optional
    @Relationship(inverse: \ProjectAssignmentTemplate.project) var sharedTemplates: [ProjectAssignmentTemplate]? = []
    @Relationship(inverse: \ProjectSession.project) var sessions: [ProjectSession]? = []

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String = "",
        bookTitle: String? = nil,
        memberStudentIDs: [String] = [],
        isActive: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.bookTitle = bookTitle
        self.memberStudentIDs = memberStudentIDs
        self.isActive = isActive
        self.sharedTemplates = []
        self.sessions = []
    }
}

@Model
final class ProjectAssignmentTemplate: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // Foreign key to Project
    // CloudKit compatibility: Store UUID as string
    var projectID: String = ""
    var project: Project?

    var title: String = ""
    var instructions: String = ""
    var isShared: Bool = true

    // Optional default link to a Lesson by UUID string
    var defaultLinkedLessonID: String? = nil
    
    // Computed property for backward compatibility with UUID
    var projectIDUUID: UUID? {
        get { UUID(uuidString: projectID) }
        set { projectID = newValue?.uuidString ?? "" }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        projectID: UUID = UUID(),
        title: String = "",
        instructions: String = "",
        isShared: Bool = true,
        defaultLinkedLessonID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        // CloudKit compatibility: Store UUID as string
        self.projectID = projectID.uuidString
        self.title = title
        self.instructions = instructions
        self.isShared = isShared
        self.defaultLinkedLessonID = defaultLinkedLessonID
    }
}

@Model
final class ProjectSession: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // Foreign key to Project
    // CloudKit compatibility: Store UUID as string
    var projectID: String = ""
    var project: Project?

    var meetingDate: Date = Date()
    var chapterOrPages: String? = nil
    var notes: String? = nil

    // Agenda from template or edited per-session (JSON encoded)
    var agendaItemsJSON: String = ""

    // Optional link back to a template week
    // CloudKit compatibility: Store UUID as string
    var templateWeekID: String? = nil

    // MARK: - Assignment Mode Configuration

    /// Raw storage for assignment mode (CloudKit compatible)
    var assignmentModeRaw: String = "uniform"

    /// For choice mode: minimum selections required per student (0 = no minimum)
    var minSelections: Int = 0

    /// For choice mode: maximum selections allowed per student (0 = unlimited)
    var maxSelections: Int = 0

    // NOTE: WorkModels are queried dynamically via sourceContextID matching this session ID.
    
    // Computed properties for backward compatibility with UUID
    var projectIDUUID: UUID? {
        get { UUID(uuidString: projectID) }
        set { projectID = newValue?.uuidString ?? "" }
    }
    
    var templateWeekIDUUID: UUID? {
        get { templateWeekID.flatMap { UUID(uuidString: $0) } }
        set { templateWeekID = newValue?.uuidString }
    }

    /// Type-safe access to assignment mode
    var assignmentMode: SessionAssignmentMode {
        get { SessionAssignmentMode(rawValue: assignmentModeRaw) ?? .uniform }
        set { assignmentModeRaw = newValue.rawValue }
    }

    // Inverse relationship for Note.projectSession
    // Note: 'notes' is a String field, so we use 'noteItems' for the relationship array
    @Relationship(deleteRule: .cascade, inverse: \Note.projectSession) var noteItems: [Note]? = []
    
    // Phase 3B: Domain-specific note types
    @Relationship(deleteRule: .cascade, inverse: \ProjectNote.projectSession) var projectNotes: [ProjectNote]? = []

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        projectID: UUID = UUID(),
        meetingDate: Date = Date(),
        chapterOrPages: String? = nil,
        notes: String? = nil,
        agendaItemsJSON: String = "",
        templateWeekID: UUID? = nil,
        assignmentMode: SessionAssignmentMode = .uniform,
        minSelections: Int = 0,
        maxSelections: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        // CloudKit compatibility: Store UUIDs as strings
        self.projectID = projectID.uuidString
        self.meetingDate = meetingDate
        self.chapterOrPages = chapterOrPages
        self.notes = notes
        self.agendaItemsJSON = agendaItemsJSON
        self.templateWeekID = templateWeekID?.uuidString
        self.assignmentModeRaw = assignmentMode.rawValue
        self.minSelections = minSelections
        self.maxSelections = maxSelections
    }

    nonisolated var agendaItems: [String] {
        get { LocalJSONStringList.decode(agendaItemsJSON) }
        set { agendaItemsJSON = LocalJSONStringList.encode(newValue) }
    }
}
