import Foundation
import SwiftData

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
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var title: String = ""
    var bookTitle: String? = nil

    // Store Student IDs as strings for CloudKit compatibility
    var memberStudentIDs: [String] = []

    // Relationships - FIX: Made optional
    @Relationship(inverse: \ProjectAssignmentTemplate.project) var sharedTemplates: [ProjectAssignmentTemplate]? = []
    @Relationship(inverse: \ProjectSession.project) var sessions: [ProjectSession]? = []

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String = "",
        bookTitle: String? = nil,
        memberStudentIDs: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.bookTitle = bookTitle
        self.memberStudentIDs = memberStudentIDs
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

    // NOTE: WorkContracts are now queried dynamically via sourceContextID matching this session ID.
    
    // Computed properties for backward compatibility with UUID
    var projectIDUUID: UUID? {
        get { UUID(uuidString: projectID) }
        set { projectID = newValue?.uuidString ?? "" }
    }
    
    var templateWeekIDUUID: UUID? {
        get { templateWeekID.flatMap { UUID(uuidString: $0) } }
        set { templateWeekID = newValue?.uuidString }
    }
    
    // Inverse relationship for Note.projectSession
    // Note: 'notes' is a String field, so we use 'noteItems' for the relationship array
    @Relationship(deleteRule: .cascade, inverse: \Note.projectSession) var noteItems: [Note]? = []

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        projectID: UUID = UUID(),
        meetingDate: Date = Date(),
        chapterOrPages: String? = nil,
        notes: String? = nil,
        agendaItemsJSON: String = "",
        templateWeekID: UUID? = nil
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
    }

    nonisolated var agendaItems: [String] {
        get { LocalJSONStringList.decode(agendaItemsJSON) }
        set { agendaItemsJSON = LocalJSONStringList.encode(newValue) }
    }
}
