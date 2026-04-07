// CommandBarViewModel.swift
// ViewModel for the natural language command bar

import Foundation
import CoreData
import OSLog

@Observable
@MainActor
final class CommandBarViewModel {
    private static let logger = Logger.app_

    // MARK: - Input

    var inputText = ""

    // MARK: - State

    var isProcessing = false
    var parsedCommand: ParsedCommand?
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
        errorMessage = nil
        commandBarService.reset()
    }

    /// Build a CommandAction from the parsed command, creating any necessary
    /// Core Data objects (like presentation drafts) using the provided context.
    func buildAction(
        from command: ParsedCommand,
        modelContext: NSManagedObjectContext
    ) -> CommandAction {
        switch command.intent {
        case .recordPresentation:
            let lessonID = command.lessonID ?? UUID()
            let draft = PresentationFactory.makeDraft(
                lessonID: lessonID,
                studentIDs: command.studentIDs,
                context: modelContext
            )
            do {
                try modelContext.save()
            } catch {
                Self.logger.warning("Failed to save presentation draft: \(error)")
            }
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

    // MARK: - Example Commands

    static let exampleCommands = [
        "I gave the binomial cube to Sarah",
        "Assign stamp game work to James",
        "CDNote: Marco was really focused on the continent maps today",
        "Remind me to call Lily's parents tomorrow"
    ]
}
