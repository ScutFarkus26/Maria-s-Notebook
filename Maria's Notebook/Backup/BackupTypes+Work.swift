import Foundation

// MARK: - Work DTOs

public struct WorkParticipantDTO: Codable, Sendable {
    public var studentID: UUID
    public var completedAt: Date?
}

public struct WorkDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var studentIDs: [UUID]
    public var workType: String
    public var assignmentUUID: UUID?
    public var createdAt: Date
    public var completedAt: Date?
    public var participants: [WorkParticipantDTO]
}

public struct WorkCheckInDTO: Codable, Sendable {
    public var id: UUID
    public var workID: String
    public var date: Date
    public var statusRaw: String
    public var purpose: String
}

public struct WorkStepDTO: Codable, Sendable {
    public var id: UUID
    public var workID: UUID?
    public var orderIndex: Int
    public var title: String
    public var instructions: String
    public var completedAt: Date?
    public var notes: String
    public var completionOutcomeRaw: String?
    public var createdAt: Date
}

public struct WorkParticipantEntityDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: String
    public var completedAt: Date?
    public var workID: UUID?
}

public struct PracticeSessionDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var date: Date
    public var duration: TimeInterval?
    public var studentIDs: [String]
    public var workItemIDs: [String]
    public var sharedNotes: String
    public var location: String?
    public var practiceQuality: Int?
    public var independenceLevel: Int?
    public var askedForHelp: Bool
    public var helpedPeer: Bool
    public var struggledWithConcept: Bool
    public var madeBreakthrough: Bool
    public var needsReteaching: Bool
    public var readyForCheckIn: Bool
    public var readyForAssessment: Bool
    public var checkInScheduledFor: Date?
    public var followUpActions: String
    public var materialsUsed: String
    public var workStepID: String?
}

public struct WorkCompletionRecordDTO: Codable, Sendable {
    public var id: UUID
    public var workID: UUID
    public var studentID: UUID
    public var completedAt: Date
}

public struct AttendanceRecordDTO: Codable, Sendable {
    public var id: UUID
    public var studentID: UUID
    public var date: Date
    public var status: String
    public var absenceReason: String?

    public init(id: UUID, studentID: UUID, date: Date, status: String, absenceReason: String? = nil) {
        self.id = id
        self.studentID = studentID
        self.date = date
        self.status = status
        self.absenceReason = absenceReason
    }
}
