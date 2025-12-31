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
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var title: String = ""
    var bookTitle: String? = nil

    // Store Student IDs as strings for CloudKit compatibility
    var memberStudentIDs: [String] = []

    // Relationships
    @Relationship(inverse: \BookClubAssignmentTemplate.bookClub) var sharedTemplates: [BookClubAssignmentTemplate]? = []
    @Relationship(inverse: \BookClubSession.bookClub) var sessions: [BookClubSession]? = []

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
final class BookClubAssignmentTemplate: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // Foreign key to BookClub
    var bookClubID: UUID = UUID()
    var bookClub: BookClub? = nil

    var title: String = ""
    var instructions: String = ""
    var isShared: Bool = true

    // Optional default link to a Lesson by UUID string
    var defaultLinkedLessonID: String? = nil

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bookClubID: UUID = UUID(),
        title: String = "",
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
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // Foreign key to BookClub
    var bookClubID: UUID = UUID()
    var bookClub: BookClub? = nil

    var meetingDate: Date = Date()
    var chapterOrPages: String? = nil
    var notes: String? = nil

    // Agenda from template or edited per-session (JSON encoded)
    var agendaItemsJSON: String = ""

    // Optional link back to a template week
    var templateWeekID: UUID? = nil

    // NOTE: WorkContracts are now queried dynamically via sourceContextID matching this session ID.

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bookClubID: UUID = UUID(),
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

