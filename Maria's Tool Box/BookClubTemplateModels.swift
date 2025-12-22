import Foundation
import SwiftData

// MARK: - JSON Helpers
struct JSONStringList {
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

// MARK: - Role
@Model
final class BookClubRole: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    var bookClubID: UUID

    var title: String
    var summary: String
    var instructions: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bookClubID: UUID,
        title: String = "",
        summary: String = "",
        instructions: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.bookClubID = bookClubID
        self.title = title
        self.summary = summary
        self.instructions = instructions
    }
}

// MARK: - Choice Set (for weekly questions)
@Model
final class BookClubChoiceSet: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    var bookClubID: UUID
    var title: String
    var requiredSelectionCount: Int

    var items: [BookClubChoiceItem]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bookClubID: UUID,
        title: String = "Weekly Questions",
        requiredSelectionCount: Int = 2,
        items: [BookClubChoiceItem] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.bookClubID = bookClubID
        self.title = title
        self.requiredSelectionCount = requiredSelectionCount
        self.items = items
    }
}

@Model
final class BookClubChoiceItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    var setID: UUID

    var title: String
    var instructions: String
    var linkedLessonID: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        setID: UUID,
        title: String = "",
        instructions: String = "",
        linkedLessonID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.setID = setID
        self.title = title
        self.instructions = instructions
        self.linkedLessonID = linkedLessonID
    }
}

// MARK: - Week Template
@Model
final class BookClubTemplateWeek: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    var bookClubID: UUID
    var weekIndex: Int

    var readingRange: String

    // Stored as JSON strings for portability
    var agendaItemsJSON: String
    var vocabSuggestionWordsJSON: String

    // Optional link to a ChoiceSet
    var questionChoiceSetID: UUID?

    // Optional requirement count for vocab deliverable (default 5)
    var vocabRequirementCount: Int

    // Relationship to assignments
    var roleAssignments: [BookClubWeekRoleAssignment]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bookClubID: UUID,
        weekIndex: Int,
        readingRange: String = "",
        agendaItemsJSON: String = "",
        vocabSuggestionWordsJSON: String = "",
        questionChoiceSetID: UUID? = nil,
        vocabRequirementCount: Int = 5,
        roleAssignments: [BookClubWeekRoleAssignment] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.bookClubID = bookClubID
        self.weekIndex = weekIndex
        self.readingRange = readingRange
        self.agendaItemsJSON = agendaItemsJSON
        self.vocabSuggestionWordsJSON = vocabSuggestionWordsJSON
        self.questionChoiceSetID = questionChoiceSetID
        self.vocabRequirementCount = vocabRequirementCount
        self.roleAssignments = roleAssignments
    }

    var agendaItems: [String] {
        get { JSONStringList.decode(agendaItemsJSON) }
        set { agendaItemsJSON = JSONStringList.encode(newValue) }
    }

    var vocabSuggestionWords: [String] {
        get { JSONStringList.decode(vocabSuggestionWordsJSON) }
        set { vocabSuggestionWordsJSON = JSONStringList.encode(newValue) }
    }
}

// MARK: - Weekly Role Assignment
@Model
final class BookClubWeekRoleAssignment: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    var weekID: UUID
    var studentID: String
    var roleID: UUID

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        weekID: UUID,
        studentID: String,
        roleID: UUID
    ) {
        self.id = id
        self.createdAt = createdAt
        self.weekID = weekID
        self.studentID = studentID
        self.roleID = roleID
    }
}
