import Foundation

// MARK: - Todo DTOs

public struct TodoItemDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var isCompleted: Bool
    public var createdAt: Date
    public var completedAt: Date?
    public var orderIndex: Int
    public var dueDate: Date?
    public var priorityRaw: String
    public var recurrenceRaw: String
    public var studentIDs: [String]
    public var linkedWorkItemID: String?
    public var attachmentPaths: [String]
    public var estimatedMinutes: Int?
    public var actualMinutes: Int?
    public var reminderDate: Date?
    public var reflectionNotes: String
    public var tags: [String]
    // Schedule fields
    public var scheduledDate: Date?
    public var isSomeday: Bool?
    public var repeatAfterCompletion: Bool?
    public var customIntervalDays: Int?
    // Location fields
    public var locationName: String?
    public var locationLatitude: Double?
    public var locationLongitude: Double?
    public var locationRadius: Double
    public var notifyOnEntry: Bool
    public var notifyOnExit: Bool
}

public struct TodoSubtaskDTO: Codable, Sendable {
    public var id: UUID
    public var todoID: UUID?
    public var title: String
    public var isCompleted: Bool
    public var orderIndex: Int
    public var createdAt: Date
    public var completedAt: Date?
}

public struct TodoTemplateDTO: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var title: String
    public var notes: String
    public var createdAt: Date
    public var priorityRaw: String
    public var defaultEstimatedMinutes: Int?
    public var defaultStudentIDs: [String]
    public var useCount: Int
    public var tags: [String]?
}

// MARK: - Track DTOs

public struct TrackDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
}

public struct TrackStepDTO: Codable, Sendable {
    public var id: UUID
    public var trackID: UUID?
    public var orderIndex: Int
    public var lessonTemplateID: UUID?
    public var createdAt: Date
}

public struct StudentTrackEnrollmentDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var studentID: String
    public var trackID: String
    public var startedAt: Date?
    public var isActive: Bool
}

public struct GroupTrackDTO: Codable, Sendable {
    public var id: UUID
    public var subject: String
    public var group: String
    public var isSequential: Bool
    public var isExplicitlyDisabled: Bool
    public var createdAt: Date
}

// MARK: - Development Snapshot DTO

public struct DevelopmentSnapshotDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var generatedAt: Date
    public var lookbackDays: Int
    public var analysisVersion: String
    public var overallProgress: String
    public var keyStrengths: [String]
    public var areasForGrowth: [String]
    public var developmentalMilestones: [String]
    public var observedPatterns: [String]
    public var behavioralTrends: [String]
    public var socialEmotionalInsights: [String]
    public var recommendedNextLessons: [String]
    public var suggestedPracticeFocus: [String]
    public var interventionSuggestions: [String]
    public var totalNotesAnalyzed: Int
    public var practiceSessionsAnalyzed: Int
    public var workCompletionsAnalyzed: Int
    public var averagePracticeQuality: Double?
    public var independenceLevel: Double?
    public var rawAnalysisJSON: String
    public var userNotes: String
    public var isReviewed: Bool
    public var sharedWithParents: Bool
    public var sharedAt: Date?
}

// MARK: - Supply DTOs

public struct SupplyDTO: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var categoryRaw: String
    public var location: String
    public var currentQuantity: Int
    public var minimumThreshold: Int
    public var reorderAmount: Int
    public var unit: String
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date
}

public struct SupplyTransactionDTO: Codable, Sendable {
    public var id: UUID
    public var supplyID: String
    public var date: Date
    public var quantityChange: Int
    public var reason: String
}

// MARK: - Document DTO

public struct DocumentDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var category: String
    public var uploadDate: Date
    public var studentID: UUID?
    // PDF data excluded by design - too large for JSON backup
}

// MARK: - Agenda Order DTO

public struct TodayAgendaOrderDTO: Codable, Sendable {
    public var id: UUID
    public var day: Date
    public var itemTypeRaw: String
    public var itemID: UUID
    public var position: Int
}
