import Foundation
import SwiftData

// Local JSON helper to avoid cross-file dependency
struct LocalJSONStringList {
    static func encode(_ arr: [String]) -> String {
        guard !arr.isEmpty else { return "" }
        if let data = try? JSONEncoder().encode(arr), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return ""
    }
    static func decode(_ s: String) -> [String] {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        if let arr = try? JSONDecoder().decode([String].self, from: data) { return arr }
        return []
    }
}

// MARK: - Models

@Model
final class BookClub: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    var title: String
    var bookTitle: String?

    // Store Student IDs as strings for CloudKit compatibility
    var memberStudentIDs: [String]

    // Relationships
    var sharedTemplates: [BookClubAssignmentTemplate]
    var sessions: [BookClubSession]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        bookTitle: String? = nil,
        memberStudentIDs: [String] = [],
        sharedTemplates: [BookClubAssignmentTemplate] = [],
        sessions: [BookClubSession] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.bookTitle = bookTitle
        self.memberStudentIDs = memberStudentIDs
        self.sharedTemplates = sharedTemplates
        self.sessions = sessions
    }
}

@Model
final class BookClubAssignmentTemplate: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    // Foreign key to BookClub
    var bookClubID: UUID

    var title: String
    var instructions: String
    var isShared: Bool

    // Optional default link to a Lesson by UUID string
    var defaultLinkedLessonID: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bookClubID: UUID,
        title: String,
        instructions: String = "",
        isShared: Bool = true,
        defaultLinkedLessonID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.bookClubID = bookClubID
        self.title = title
        self.instructions = instructions
        self.isShared = isShared
        self.defaultLinkedLessonID = defaultLinkedLessonID
    }
}

@Model
final class BookClubSession: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    // Foreign key to BookClub
    var bookClubID: UUID

    var meetingDate: Date
    var chapterOrPages: String?
    var notes: String?

    // Agenda from template or edited per-session (JSON encoded)
    var agendaItemsJSON: String

    // Optional link back to a template week
    var templateWeekID: UUID?

    // NOTE: WorkContracts are now queried dynamically via sourceContextID matching this session ID.

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bookClubID: UUID,
        meetingDate: Date = Date(),
        chapterOrPages: String? = nil,
        notes: String? = nil,
        agendaItemsJSON: String = "",
        templateWeekID: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.bookClubID = bookClubID
        self.meetingDate = meetingDate
        self.chapterOrPages = chapterOrPages
        self.notes = notes
        self.agendaItemsJSON = agendaItemsJSON
        self.templateWeekID = templateWeekID
    }

    var agendaItems: [String] {
        get { LocalJSONStringList.decode(agendaItemsJSON) }
        set { agendaItemsJSON = LocalJSONStringList.encode(newValue) }
    }
}
