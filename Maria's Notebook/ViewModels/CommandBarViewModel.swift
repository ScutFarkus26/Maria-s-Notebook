// CommandBarViewModel.swift
// ViewModel for the natural language command bar

import Foundation
import CoreData

@Observable
final class CommandBarViewModel {
    // MARK: - Input

    var inputText = ""

    // MARK: - State

    var isProcessing = false
    var parsedCommand: ParsedCommand?
    var captureProposal: CaptureProposal?
    var errorMessage: String?

    // MARK: - Recent Commands

    private static let recentCommandsKey = "commandBarRecentCommands"
    private static let maxRecent = 10

    var recentCommands: [String] {
        get {
            (UserDefaults.standard.array(forKey: Self.recentCommandsKey) as? [String]) ?? []
        }
        set {
            UserDefaults.standard.set(Array(newValue.prefix(Self.maxRecent)), forKey: Self.recentCommandsKey)
        }
    }

    func addToRecent(_ command: String) {
        var recent = recentCommands
        recent.removeAll { $0 == command }
        recent.insert(command, at: 0)
        recentCommands = recent
    }

    // MARK: - Services

    private let commandBarService = CommandBarService()
    let speechService = SpeechRecognitionService()

    // MARK: - Public Methods

    func submit(students: [StudentData], lessons: [LessonData], mcpClient: MCPClientProtocol?) async {
        let trimmed = inputText.trimmed()
        guard !trimmed.isEmpty else { return }

        isProcessing = true
        parsedCommand = nil
        captureProposal = nil
        errorMessage = nil

        await commandBarService.parse(
            input: trimmed,
            students: students,
            lessons: lessons,
            mcpClient: mcpClient
        )

        switch commandBarService.parseState {
        case .result(let cmd):
            parsedCommand = cmd
        case .capture(let proposal):
            captureProposal = proposal
        case .error(let msg):
            errorMessage = msg
        default:
            break
        }

        isProcessing = false
    }

    func reset() {
        inputText = ""
        isProcessing = false
        parsedCommand = nil
        captureProposal = nil
        errorMessage = nil
        commandBarService.reset()
    }

    /// Build a CommandAction from the parsed command, creating any necessary
    /// Core Data objects (like presentation drafts) using the provided context.
    func buildAction(
        from command: ParsedCommand,
        modelContext: NSManagedObjectContext
    ) -> CommandAction? {
        switch command.intent {
        case .recordPresentation:
            guard let lessonID = command.lessonID else {
                errorMessage = "Choose a lesson before opening the presentation. Nothing was saved."
                return nil
            }
            let draft = PresentationFactory.makeDraft(
                lessonID: lessonID,
                studentIDs: command.studentIDs,
                context: modelContext
            )
            modelContext.safeSave()
            return .openPresentation(draftID: draft.id ?? UUID())

        case .assignWork:
            return .openWorkItem(
                lessonID: command.lessonID,
                studentIDs: Set(command.studentIDs)
            )

        case .recordPractice:
            return .openPractice(
                lessonID: command.lessonID,
                studentIDs: Set(command.studentIDs)
            )

        case .addNote:
            let bodyText = command.freeText.isEmpty ? inputText : command.freeText
            return .openNote(
                studentIDs: Set(command.studentIDs),
                bodyText: bodyText,
                inferredTags: command.inferredTags
            )

        case .addTodo:
            let title = command.freeText.isEmpty ? inputText : command.freeText
            return .openTodo(titleText: title)
        }
    }

    // MARK: - Editable Capture Proposal

    func setStudent(_ student: StudentData, isSelected: Bool) {
        guard var proposal = captureProposal else { return }
        if isSelected {
            guard !proposal.studentEntries.contains(where: { $0.studentID == student.id }) else { return }
            proposal.studentEntries.append(StudentCaptureProposal(
                studentID: student.id,
                studentName: "\(student.firstName) \(student.lastName)"
            ))
        } else {
            proposal.studentEntries.removeAll { $0.studentID == student.id }
        }
        captureProposal = proposal
    }

    func updateStudentEntry(
        id: UUID,
        _ update: (inout StudentCaptureProposal) -> Void
    ) {
        guard var proposal = captureProposal,
              let index = proposal.studentEntries.firstIndex(where: { $0.id == id }) else { return }
        update(&proposal.studentEntries[index])
        captureProposal = proposal
    }

    var captureValidationMessage: String? {
        guard let proposal = captureProposal else { return "There is nothing to review." }

        if proposal.recordsPresentation {
            if proposal.lessonID == nil { return "Choose the lesson that was given." }
            if proposal.studentEntries.isEmpty { return "Choose at least one child who received the lesson." }
        }

        if !proposal.recordsPresentation,
           proposal.studentEntries.contains(where: { $0.followUp != .none }) {
            return "Record the presentation before choosing a presentation follow-up."
        }

        if proposal.studentEntries.contains(where: {
            $0.followUp == .continueObserving && $0.observation.trimmed().isEmpty
        }) {
            return "Add what you want to keep observing, or choose No decision yet."
        }

        if proposal.studentEntries.contains(where: {
            $0.followUp == .followUpWork && $0.followUpDetail.trimmed().isEmpty
        }) {
            return "Describe the specific follow-up work."
        }

        if !proposal.hasAnythingToSave {
            return "Add a presentation or observation before saving."
        }
        return nil
    }

    // MARK: - Example Commands

    static let exampleCommands = [
        "I gave the binomial cube to Sarah. She completed it twice and I want to keep observing.",
        "I showed stamp game to James and Maya. James worked independently; offer Maya more practice.",
        "Marco chose the continent map three times and returned every piece to the tray.",
        "I presented noun family to Leah. She is ready for the next lesson."
    ]
}

enum CaptureSaveError: LocalizedError {
    case invalid(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .saveFailed(let message): return message
        }
    }
}
