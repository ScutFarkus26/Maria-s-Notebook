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

// MARK: - Week Template
@Model
final class BookClubTemplateWeek: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    var bookClubID: UUID
    var weekIndex: Int

    var readingRange: String

    // Stored as JSON strings for portability
    // CRITICAL FIX: Default values added here ("") to prevent migration crashes
    var agendaItemsJSON: String = ""
    var linkedLessonIDsJSON: String = ""

    // Simplified Instructions (replaces vocab/questions)
    // CRITICAL FIX: Default value added here ("")
    var workInstructions: String = ""

    // Relationship to assignments
    var roleAssignments: [BookClubWeekRoleAssignment]
    
    // Deprecated fields (Optional to keep for migration safety)
    var questionChoiceSetID: UUID?
    var vocabSuggestionWordsJSON: String
    var vocabRequirementCount: Int
    var linkedLessonID: String? // Old single lesson link

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bookClubID: UUID,
        weekIndex: Int,
        readingRange: String = "",
        agendaItemsJSON: String = "",
        linkedLessonIDsJSON: String = "",
        workInstructions: String = "",
        roleAssignments: [BookClubWeekRoleAssignment] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.bookClubID = bookClubID
        self.weekIndex = weekIndex
        self.readingRange = readingRange
        self.agendaItemsJSON = agendaItemsJSON
        self.linkedLessonIDsJSON = linkedLessonIDsJSON
        self.workInstructions = workInstructions
        self.roleAssignments = roleAssignments
        
        // Defaults for deprecated fields
        self.questionChoiceSetID = nil
        self.vocabSuggestionWordsJSON = ""
        self.vocabRequirementCount = 0
        self.linkedLessonID = nil
    }

    var agendaItems: [String] {
        get { JSONStringList.decode(agendaItemsJSON) }
        set { agendaItemsJSON = JSONStringList.encode(newValue) }
    }
    
    var linkedLessonIDs: [String] {
        get { JSONStringList.decode(linkedLessonIDsJSON) }
        set { linkedLessonIDsJSON = JSONStringList.encode(newValue) }
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

// MARK: - Legacy Choice Models (Kept to prevent database errors, but unused in new flow)
@Model
final class BookClubChoiceSet: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var bookClubID: UUID
    var title: String
    var requiredSelectionCount: Int
    var items: [BookClubChoiceItem]

    init(id: UUID = UUID(), createdAt: Date = Date(), bookClubID: UUID, title: String = "", requiredSelectionCount: Int = 0, items: [BookClubChoiceItem] = []) {
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

    init(id: UUID = UUID(), createdAt: Date = Date(), setID: UUID, title: String = "", instructions: String = "", linkedLessonID: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.setID = setID
        self.title = title
        self.instructions = instructions
        self.linkedLessonID = linkedLessonID
    }
}
