// CommandBarViewModel.swift
// ViewModel for the natural language command bar

import Foundation

@Observable
final class CommandBarViewModel {
    // MARK: - Input

    var inputText = ""

    // MARK: - State

    var isProcessing = false
    /// A Send is under way: waiting for dictation's last words, then
    /// organizing. Another Send or Return meanwhile is ignored; it used to
    /// organize the words twice and put both in Recent.
    private(set) var isSending = false
    var parsedCommand: ParsedCommand?
    var captureProposal: CaptureProposal?
    var errorMessage: String?

    // MARK: - Recent Commands

    private static let recentCommandsKey = "commandBarRecentCommands"
    private static let sampleRecentCommandsKey = "commandBarRecentCommands.sampleClass"
    private static let maxRecent = 10

    /// Sample Class keeps its own history: the guide's real captures name her
    /// real children, who aren't in the sample, and practice captures made in
    /// the sample shouldn't turn up in her class.
    var isSampleClassroom = false

    private var recentCommandsKey: String {
        isSampleClassroom ? Self.sampleRecentCommandsKey : Self.recentCommandsKey
    }

    var recentCommands: [String] {
        get {
            (UserDefaults.standard.array(forKey: recentCommandsKey) as? [String]) ?? []
        }
        set {
            UserDefaults.standard.set(Array(newValue.prefix(Self.maxRecent)), forKey: recentCommandsKey)
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

    /// What the current dictation last put in the field; `nil` until it has
    /// put anything there.
    @ObservationIgnored private var lastDictatedText: String?

    init() {
        speechService.onDictatedText = { [weak self] text in
            self?.applyDictatedText(text)
        }
    }

    // MARK: - Public Methods

    /// Sends the field's words to be organized, once any dictation still
    /// running or finishing has put its last words in.
    func send(students: [StudentData], lessons: [LessonData]) async {
        guard !isSending, !isProcessing else { return }
        isSending = true
        defer { isSending = false }
        await finishDictation()
        await submit(students: students, lessons: lessons)
    }

    func submit(students: [StudentData], lessons: [LessonData]) async {
        let trimmed = inputText.trimmed()
        guard !trimmed.isEmpty else { return }

        isProcessing = true
        parsedCommand = nil
        captureProposal = nil
        errorMessage = nil

        await commandBarService.parse(
            input: trimmed,
            students: students,
            lessons: lessons
        )

        switch commandBarService.parseState {
        case .result(let cmd):
            parsedCommand = cmd
        case .capture(let proposal):
            captureProposal = proposal
            // In Recent from now on, so closing the review without saving
            // never loses her words (bug hunt 2026-10-11 #47).
            addToRecent(trimmed)
        case .error(let msg):
            errorMessage = msg
        default:
            break
        }

        isProcessing = false
    }

    /// Ends a dictation still running, or waits for one already finishing,
    /// so its last words (they arrive after the microphone stops) are in the
    /// field before the text is read.
    func finishDictation() async {
        await speechService.finishRecording()
    }

    /// Starts or stops dictation from the mic button.
    func toggleDictation() {
        if !speechService.isRecording { lastDictatedText = nil }
        speechService.toggleRecording(appendingTo: inputText)
    }

    /// Puts the dictation's words in the field, unless she has typed or
    /// picked something since they last went in: her own words win. Without
    /// this, words arriving after she stopped the mic and typed ", twice"
    /// wiped what she typed (review (b) 2026-10-11).
    private func applyDictatedText(_ text: String) {
        guard inputText == (lastDictatedText ?? speechService.typedBeforeDictation) else { return }
        inputText = text
        lastDictatedText = text
    }

    func reset() {
        inputText = ""
        isProcessing = false
        parsedCommand = nil
        captureProposal = nil
        errorMessage = nil
        commandBarService.reset()
    }

    /// The form a one-step command opens. `CommandBarService` sends only work,
    /// practice and todo commands here; presentations and notes become a
    /// capture to review.
    func buildAction(from command: ParsedCommand) -> CommandAction? {
        switch command.intent {
        case .recordPresentation, .addNote:
            return nil

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

        case .addTodo:
            let title = command.freeText.isEmpty ? inputText : command.freeText
            return .openTodo(titleText: title)
        }
    }

    // MARK: - Editable Capture Proposal

    var captureValidationMessage: String? {
        guard let proposal = captureProposal else { return "There is nothing to review." }

        // A name the organizer couldn't place would otherwise be saved without
        // her, and what was said about her lost (bug hunt 2026-10-11 #46).
        if !proposal.unresolvedStudentNames.isEmpty {
            let names = ListFormatter.localizedString(byJoining: proposal.unresolvedStudentNames.map { "“\($0)”" })
            return "Choose who \(names) \(proposal.unresolvedStudentNames.count == 1 ? "is" : "are"), "
                + "or tap Leave Out."
        }

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

/// Why a reviewed capture wasn't saved, each in plain words for the review
/// screen. Nothing is ever half-saved: every case leaves the notebook as it was.
enum CaptureSaveError: LocalizedError, Equatable {
    /// A review-screen check (`captureValidationMessage`), already plain.
    case invalid(String)
    case studentMissing
    case lessonMissing
    /// The notebook couldn't save; the raw error is in the log.
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        case .studentMissing:
            return "One of these children is no longer in your class. Check the names and try again."
        case .lessonMissing:
            return "Couldn't find that lesson. It may have been deleted. Nothing was saved."
        case .saveFailed:
            return "Couldn't save what you wrote. Nothing was changed. Try again."
        }
    }
}
