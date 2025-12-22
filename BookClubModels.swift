import Foundation
import SwiftData

// MARK: - Deliverable Status

enum BookClubDeliverableStatus: String, Codable, CaseIterable {
    case assigned
    case inProgress
    case readyForReview
    case completed
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

    // Relationships
    var deliverables: [BookClubDeliverable]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bookClubID: UUID,
        meetingDate: Date = Date(),
        chapterOrPages: String? = nil,
        notes: String? = nil,
        deliverables: [BookClubDeliverable] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.bookClubID = bookClubID
        self.meetingDate = meetingDate
        self.chapterOrPages = chapterOrPages
        self.notes = notes
        self.deliverables = deliverables
    }
}

@Model
final class BookClubDeliverable: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    // Foreign key to BookClubSession
    var sessionID: UUID

    // Student ID as String (UUID string)
    var studentID: String

    // Optional reference to a template
    var templateID: UUID?

    var title: String
    var instructions: String
    var dueDate: Date?

    // Status stored as raw string
    var statusRaw: String

    // Optional link to a Lesson by UUID string
    var linkedLessonID: String?

    // If a WorkContract was generated from this deliverable, store its ID
    var generatedWorkID: UUID?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sessionID: UUID,
        studentID: String,
        templateID: UUID? = nil,
        title: String,
        instructions: String = "",
        dueDate: Date? = nil,
        status: BookClubDeliverableStatus = .assigned,
        linkedLessonID: String? = nil,
        generatedWorkID: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sessionID = sessionID
        self.studentID = studentID
        self.templateID = templateID
        self.title = title
        self.instructions = instructions
        self.dueDate = dueDate
        self.statusRaw = status.rawValue
        self.linkedLessonID = linkedLessonID
        self.generatedWorkID = generatedWorkID
    }

    var status: BookClubDeliverableStatus {
        get { BookClubDeliverableStatus(rawValue: statusRaw) ?? .assigned }
        set { statusRaw = newValue.rawValue }
    }
}
