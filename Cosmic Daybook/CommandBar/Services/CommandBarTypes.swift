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
nonisolated struct ParsedCommand: Sendable {
    let intent: RecordIntent
    let studentIDs: [UUID]
    let lessonID: UUID?
    let rawStudentNames: [String]
    let rawLessonName: String?
    let freeText: String
    let inferredTags: [String]
    let confidence: Double
    /// Names the parser saw but couldn't settle on one child: a first name
    /// two children share. The capture review asks who was meant.
    var unresolvedStudentNames: [String] = []

    static let confidenceThreshold: Double = 0.6
}

// MARK: - Capture What Happened

/// Identifies how an editable capture proposal was organized. Both paths stay
/// on the device; the deterministic path is used when the Foundation Models
/// framework or the system model is unavailable.
nonisolated enum CaptureProposalSource: Sendable {
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
nonisolated enum CaptureFollowUp: String, CaseIterable, Identifiable, Sendable {
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
nonisolated struct StudentCaptureProposal: Identifiable, Sendable {
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
nonisolated struct CaptureProposal: Sendable {
    var rawText: String
    var recordsPresentation: Bool
    var lessonID: UUID?
    var lessonName: String?
    var groupObservation: String
    var studentEntries: [StudentCaptureProposal]
    /// Names the organizer couldn't place on one child. Save waits until the
    /// guide picks who was meant or leaves the name out.
    var unresolvedStudentNames: [String]
    var source: CaptureProposalSource
    /// The day it happened (start of day): the presentation and the notes are
    /// saved on it. Taken from the guide's words when they name one
    /// (`CaptureDateParser`), today otherwise; she can change it on the review
    /// screen. (The name predates notes using it too.)
    var presentedOn: Date = AppCalendar.startOfDay(Date())
    /// What was said about each unresolved name, keyed by the name as listed.
    var unplacedWords: [String: UnplacedStudentWords] = [:]

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

/// What the guide said about a child the organizer couldn't place: a first
/// name two children share, or a name that matched nobody. It is kept with
/// the name until she picks who was meant, then goes to that child's entry.
nonisolated struct UnplacedStudentWords: Sendable, Equatable {
    var observation: String = ""
    var followUp: CaptureFollowUp = .none
    var followUpDetail: String = ""
}

extension CaptureProposal {
    /// Adds or removes a child the guide picked on the review screen.
    /// `displayName` is the name her chip shows.
    ///
    /// Picking a child settles only the unplaced names she could be ("Etty"
    /// for Etty D, not "Sarah"), and brings what was said about that name
    /// into her entry. Taking a child off again leaves the names alone.
    ///
    /// A name that matches nobody in `roster` (a misheard "Eddie") can't be
    /// settled that way. When it is the only name left, the child she picks
    /// is taken to be who was meant, so what was said about it isn't lost
    /// to Leave Out (review (b) 2026-10-11). Without a roster no name is
    /// taken to match nobody.
    mutating func setStudent(
        _ student: StudentData, named displayName: String, isSelected: Bool, roster: [StudentData]? = nil
    ) {
        guard isSelected else {
            studentEntries.removeAll { $0.studentID == student.id }
            return
        }
        guard !studentEntries.contains(where: { $0.studentID == student.id }) else { return }
        var entry = StudentCaptureProposal(studentID: student.id, studentName: displayName)
        var settled = unresolvedStudentNames.filter { Self.name($0, couldMean: student) }
        if settled.isEmpty, let roster, unresolvedStudentNames.count == 1, let only = unresolvedStudentNames.first,
           !roster.contains(where: { Self.name(only, couldMean: $0) }) {
            settled = [only]
        }
        for name in settled {
            guard let words = unplacedWords.removeValue(forKey: name) else { continue }
            entry.take(words)
        }
        unresolvedStudentNames.removeAll { settled.contains($0) }
        studentEntries.append(entry)
        studentEntries.sort { lhs, rhs in
            lhs.studentName.localizedStandardCompare(rhs.studentName) == .orderedAscending
        }
    }

    /// The guide says a name is nobody in her class: it, and what was said
    /// about it, are left out.
    mutating func leaveOutUnplacedName(_ name: String) {
        unresolvedStudentNames.removeAll { $0 == name }
        unplacedWords[name] = nil
    }

    /// Whether an unplaced name could be this child: her first name, full
    /// name, short name ("Etty D", with or without the period) or nickname.
    static func name(_ name: String, couldMean student: StudentData) -> Bool {
        var token = name.folded()
        if token.hasSuffix(".") { token.removeLast() }
        guard !token.isEmpty else { return false }
        let first = student.firstName.folded()
        let last = student.lastName.folded()
        let nickname = (student.nickname ?? "").folded()
        let forms = [first, "\(first) \(last)", last.first.map { "\(first) \($0)" } ?? first, nickname]
        return forms.contains { !$0.isEmpty && $0 == token }
    }
}

private extension StudentCaptureProposal {
    /// Adds what was said about her unplaced name to what her entry already holds.
    mutating func take(_ words: UnplacedStudentWords) {
        let said = words.observation.trimmed()
        if !said.isEmpty {
            observation = observation.trimmed().isEmpty ? said : "\(observation.trimmed()) \(said)"
        }
        if followUp == .none, words.followUp != .none {
            followUp = words.followUp
            followUpDetail = words.followUpDetail
        }
    }
}

struct CaptureSaveReceipt: Sendable {
    let presentationID: UUID?
    let noteIDs: [UUID]
    let workCount: Int

    var noteCount: Int { noteIDs.count }
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

/// The form a one-step command opens. Presentations and notes never come
/// here: they are organized into a capture to review instead.
enum CommandAction: Equatable {
    case openWorkItem(lessonID: UUID?, studentIDs: Set<UUID>)
    case openPractice(lessonID: UUID?, studentIDs: Set<UUID>)
    case openTodo(titleText: String)
}
