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
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var bookClubID: UUID = UUID()

    var title: String = ""
    var summary: String = ""
    var instructions: String = ""

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
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var bookClubID: UUID = UUID()
    var weekIndex: Int = 0

    var readingRange: String = ""

    // Stored as JSON strings for portability
    // CRITICAL FIX: Default values added here ("") to prevent migration crashes
    var agendaItemsJSON: String = ""
    var linkedLessonIDsJSON: String = ""

    // Simplified Instructions (replaces vocab/questions)
    // CRITICAL FIX: Default value added here ("")
    var workInstructions: String = ""

    // Relationship to assignments - FIX: Made optional
    @Relationship(inverse: \BookClubWeekRoleAssignment.week)
    var roleAssignments: [BookClubWeekRoleAssignment]? = []
    

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bookClubID: UUID,
        weekIndex: Int,
        readingRange: String = "",
        agendaItemsJSON: String = "",
        linkedLessonIDsJSON: String = "",
        workInstructions: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.bookClubID = bookClubID
        self.weekIndex = weekIndex
        self.readingRange = readingRange
        self.agendaItemsJSON = agendaItemsJSON
        self.linkedLessonIDsJSON = linkedLessonIDsJSON
        self.workInstructions = workInstructions
        self.roleAssignments = []
        
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
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var weekID: UUID = UUID()
    var studentID: String = ""
    var roleID: UUID = UUID()

    // FIX: Removed @Relationship macro here to break circular dependency.
    // The relationship is managed by the parent (BookClubTemplateWeek).
    var week: BookClubTemplateWeek?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        weekID: UUID,
        studentID: String,
        roleID: UUID,
        week: BookClubTemplateWeek? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.weekID = weekID
        self.studentID = studentID
        self.roleID = roleID
        self.week = week
    }
}

