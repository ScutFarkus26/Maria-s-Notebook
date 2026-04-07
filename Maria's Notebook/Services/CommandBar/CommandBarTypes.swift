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
