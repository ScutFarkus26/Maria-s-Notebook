import Foundation
import OSLog
import SwiftData

// MARK: - JSON Helpers
struct JSONStringList {
    private static let logger = Logger.projects
    nonisolated static func encode(_ arr: [String]) -> String {
        guard !arr.isEmpty else { return "" }
        do {
            let data = try JSONEncoder().encode(arr)
            if let s = String(data: data, encoding: .utf8) {
                return s
            }
        } catch {
            Self.logger.warning("Failed to encode string array: \(error)")
        }
        return ""
    }
    nonisolated static func decode(_ s: String) -> [String] {
        let trimmed = s.trimmed()
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        do {
            let arr = try JSONDecoder().decode([String].self, from: data)
            return arr
        } catch {
            Self.logger.warning("Failed to decode string array: \(error)")
            return []
        }
    }
}

// MARK: - Template Offered Work

/// Represents a work offer in a template (stored as JSON)
struct TemplateOfferedWork: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String = ""
    var instructions: String = ""

    init(id: String = UUID().uuidString, title: String = "", instructions: String = "") {
        self.id = id
        self.title = title
        self.instructions = instructions
    }
}

// MARK: - Template Offered Works JSON Helper
struct TemplateOfferedWorksJSON {
    private static let logger = Logger.projects
    nonisolated static func encode(_ works: [TemplateOfferedWork]) -> String {
        guard !works.isEmpty else { return "" }
        do {
            let data = try JSONEncoder().encode(works)
            if let s = String(data: data, encoding: .utf8) {
                return s
            }
        } catch {
            Self.logger.warning("Failed to encode template offered works: \(error)")
        }
        return ""
    }
    nonisolated static func decode(_ s: String) -> [TemplateOfferedWork] {
        let trimmed = s.trimmed()
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        do {
            let arr = try JSONDecoder().decode([TemplateOfferedWork].self, from: data)
            return arr
        } catch {
            Self.logger.warning("Failed to decode template offered works: \(error)")
            return []
        }
    }
}

// MARK: - Role
@Model
final class ProjectRole: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // CloudKit compatibility: Store UUID as string
    var projectID: String = ""

    var title: String = ""
    var summary: String = ""
    var instructions: String = ""
    
    // Computed property for backward compatibility with UUID
    var projectIDUUID: UUID? {
        get { UUID(uuidString: projectID) }
        set { projectID = newValue?.uuidString ?? "" }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        projectID: UUID,
        title: String = "",
        summary: String = "",
        instructions: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        // CloudKit compatibility: Store UUID as string
        self.projectID = projectID.uuidString
        self.title = title
        self.summary = summary
        self.instructions = instructions
    }
}

// MARK: - Week Template
@Model
final class ProjectTemplateWeek: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // CloudKit compatibility: Store UUID as string
    var projectID: String = ""
    var weekIndex: Int = 0

    var readingRange: String = ""

    // Stored as JSON strings for portability
    // CRITICAL FIX: Default values added here ("") to prevent migration crashes
    var agendaItemsJSON: String = ""
    var linkedLessonIDsJSON: String = ""

    // Simplified Instructions (replaces vocab/questions)
    // CRITICAL FIX: Default value added here ("")
    var workInstructions: String = ""

    // MARK: - Assignment Mode Configuration

    /// Raw storage for assignment mode (CloudKit compatible)
    var assignmentModeRaw: String = "uniform"

    /// For choice mode: minimum selections required per student
    var minSelections: Int = 0

    /// For choice mode: maximum selections allowed per student (0 = unlimited)
    var maxSelections: Int = 0

    /// Offered works for choice mode (stored as JSON)
    var offeredWorksJSON: String = ""

    // Relationship to assignments - FIX: Made optional
    @Relationship(inverse: \ProjectWeekRoleAssignment.week)
    var roleAssignments: [ProjectWeekRoleAssignment]? = []
    

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        projectID: UUID,
        weekIndex: Int,
        readingRange: String = "",
        agendaItemsJSON: String = "",
        linkedLessonIDsJSON: String = "",
        workInstructions: String = "",
        assignmentMode: SessionAssignmentMode = .uniform,
        minSelections: Int = 0,
        maxSelections: Int = 0,
        offeredWorksJSON: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        // CloudKit compatibility: Store UUID as string
        self.projectID = projectID.uuidString
        self.weekIndex = weekIndex
        self.readingRange = readingRange
        self.agendaItemsJSON = agendaItemsJSON
        self.linkedLessonIDsJSON = linkedLessonIDsJSON
        self.workInstructions = workInstructions
        self.assignmentModeRaw = assignmentMode.rawValue
        self.minSelections = minSelections
        self.maxSelections = maxSelections
        self.offeredWorksJSON = offeredWorksJSON
        self.roleAssignments = []
    }

    nonisolated var agendaItems: [String] {
        get { JSONStringList.decode(agendaItemsJSON) }
        set { agendaItemsJSON = JSONStringList.encode(newValue) }
    }
    
    nonisolated var linkedLessonIDs: [String] {
        get { JSONStringList.decode(linkedLessonIDsJSON) }
        set { linkedLessonIDsJSON = JSONStringList.encode(newValue) }
    }

    /// Type-safe access to assignment mode
    var assignmentMode: SessionAssignmentMode {
        get { SessionAssignmentMode(rawValue: assignmentModeRaw) ?? .uniform }
        set { assignmentModeRaw = newValue.rawValue }
    }

    /// Type-safe access to offered works
    nonisolated var offeredWorks: [TemplateOfferedWork] {
        get { TemplateOfferedWorksJSON.decode(offeredWorksJSON) }
        set { offeredWorksJSON = TemplateOfferedWorksJSON.encode(newValue) }
    }

    // Computed property for backward compatibility with UUID
    var projectIDUUID: UUID? {
        get { UUID(uuidString: projectID) }
        set { projectID = newValue?.uuidString ?? "" }
    }
}

// MARK: - Weekly Role Assignment
@Model
final class ProjectWeekRoleAssignment: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // CloudKit compatibility: Store UUIDs as strings
    var weekID: String = ""
    var studentID: String = ""
    var roleID: String = ""

    // FIX: Removed @Relationship macro here to break circular dependency.
    // The relationship is managed by the parent (ProjectTemplateWeek).
    var week: ProjectTemplateWeek?
    
    // Computed properties for backward compatibility with UUID
    var weekIDUUID: UUID? {
        get { UUID(uuidString: weekID) }
        set { weekID = newValue?.uuidString ?? "" }
    }
    
    var roleIDUUID: UUID? {
        get { UUID(uuidString: roleID) }
        set { roleID = newValue?.uuidString ?? "" }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        weekID: UUID,
        studentID: String,
        roleID: UUID,
        week: ProjectTemplateWeek? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        // CloudKit compatibility: Store UUIDs as strings
        self.weekID = weekID.uuidString
        self.studentID = studentID
        self.roleID = roleID.uuidString
        self.week = week
    }
}

