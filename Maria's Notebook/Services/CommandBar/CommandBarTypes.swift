// CommandBarTypes.swift
// Data types for the natural language command bar

import Foundation

// MARK: - Record Intent

/// The intent detected from natural language input
enum RecordIntent: String, Codable, CaseIterable, Sendable {
    case recordPresentation  // gave, presented, showed, demonstrated
    case assignWork          // assign, work
    case recordPractice      // practiced, practicing, practice
    case addNote             // note, observe, noticed, saw
    case addTodo             // todo, remind, reminder, task

    var displayName: String {
        switch self {
        case .recordPresentation: return "Presentation"
        case .assignWork: return "Work"
        case .recordPractice: return "Practice"
        case .addNote: return "Note"
        case .addTodo: return "Todo"
        }
    }

    var icon: String {
        switch self {
        case .recordPresentation: return "person.crop.rectangle.stack"
        case .assignWork: return "tray.and.arrow.down"
        case .recordPractice: return "figure.run"
        case .addNote: return "square.and.pencil"
        case .addTodo: return "checklist.checked"
        }
    }

    var pieMenuAction: PieMenuAction {
        switch self {
        case .recordPresentation: return .newPresentation
        case .assignWork: return .newWorkItem
        case .recordPractice: return .recordPractice
        case .addNote: return .newNote
        case .addTodo: return .newTodo
        }
    }
}

// MARK: - Parsed Command

/// The result of parsing natural language input into structured data
struct ParsedCommand: Sendable {
    let intent: RecordIntent
    let studentIDs: [UUID]
    let lessonID: UUID?
    let rawStudentNames: [String]
    let rawLessonName: String?
    let freeText: String
    let inferredTags: [String]
    let confidence: Double

    static let confidenceThreshold: Double = 0.6
}

// MARK: - Capture What Happened

/// Identifies how an editable capture proposal was organized. Both paths stay
/// on the device; the deterministic path is used when the Foundation Models
/// framework or the system model is unavailable.
enum CaptureProposalSource: Sendable {
    case appleIntelligence
    case deterministic

    var disclosure: String {
        switch self {
        case .appleIntelligence:
            return "Organized by Apple Intelligence on this device"
        case .deterministic:
            return "Organized privately on this device"
        }
    }

    var icon: String {
        switch self {
        case .appleIntelligence: return "apple.intelligence"
        case .deterministic: return "lock.shield"
        }
    }
}

/// A guide-confirmed next step. `.none` is deliberately the default: the app
/// never invents practice, readiness, or follow-up work from an observation.
enum CaptureFollowUp: String, CaseIterable, Identifiable, Sendable {
    case none
    case continueObserving
    case practice
    case represent
    case readyForNextLesson
    case followUpWork

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No decision yet"
        case .continueObserving: return "Continue observing"
        case .practice: return "Offer practice"
        case .represent: return "Re-present the lesson"
        case .readyForNextLesson: return "Ready for the next lesson"
        case .followUpWork: return "Specific follow-up work"
        }
    }

    var icon: String {
        switch self {
        case .none: return "minus.circle"
        case .continueObserving: return "eye"
        case .practice: return "repeat"
        case .represent: return "arrow.counterclockwise"
        case .readyForNextLesson: return "checkmark.circle"
        case .followUpWork: return "text.badge.plus"
        }
    }
}

/// One child's editable portion of a classroom capture.
struct StudentCaptureProposal: Identifiable, Sendable {
    let id: UUID
    var studentID: UUID
    var studentName: String
    var observation: String
    var followUp: CaptureFollowUp
    var followUpDetail: String

    init(
        studentID: UUID,
        studentName: String,
        observation: String = "",
        followUp: CaptureFollowUp = .none,
        followUpDetail: String = ""
    ) {
        self.id = studentID
        self.studentID = studentID
        self.studentName = studentName
        self.observation = observation
        self.followUp = followUp
        self.followUpDetail = followUpDetail
    }
}

/// A reviewable proposal produced from one spoken or typed classroom account.
/// This value is intentionally separate from Core Data: parsing cannot save.
struct CaptureProposal: Sendable {
    var rawText: String
    var recordsPresentation: Bool
    var lessonID: UUID?
    var lessonName: String?
    var groupObservation: String
    var studentEntries: [StudentCaptureProposal]
    var unresolvedStudentNames: [String]
    var source: CaptureProposalSource

    var studentIDs: [UUID] {
        studentEntries.map(\.studentID)
    }

    var hasAnythingToSave: Bool {
        if recordsPresentation, lessonID != nil, !studentEntries.isEmpty {
            return true
        }
        if !groupObservation.trimmed().isEmpty {
            return true
        }
        return studentEntries.contains { !$0.observation.trimmed().isEmpty }
    }
}

struct CaptureSaveReceipt: Sendable {
    let presentationID: UUID?
    let noteCount: Int
    let workCount: Int
}

// MARK: - Parse Result

/// Outcome of the parsing pipeline
enum CommandParseResult: Sendable {
    case parsed(ParsedCommand)
    case ambiguous(suggestions: [ParsedCommand])
    case failed(reason: String)
}

// MARK: - Quick Note Parameters

/// Identifiable wrapper for QuickNote sheet presentation via .sheet(item:).
/// Using item-based presentation forces SwiftUI to create a fresh view identity
/// each time, ensuring @State is properly initialized with the provided values.
struct QuickNoteParams: Identifiable {
    let id = UUID()
    let studentIDs: Set<UUID>
    let bodyText: String
    let tags: [String]

    init(studentIDs: Set<UUID> = [], bodyText: String = "", tags: [String] = []) {
        self.studentIDs = studentIDs
        self.bodyText = bodyText
        self.tags = tags
    }
}

// MARK: - Command Action

/// The action to execute after a successful parse, used to route to the correct sheet
enum CommandAction {
    case openPresentation(draftID: UUID)
    case openWorkItem(lessonID: UUID?, studentIDs: Set<UUID>)
    case openPractice(lessonID: UUID?, studentIDs: Set<UUID>)
    case openNote(studentIDs: Set<UUID>, bodyText: String, inferredTags: [String])
    case openTodo(titleText: String)
}
