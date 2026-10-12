import CoreData
import Foundation
import Synchronization
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11, agent M: the command bar's names it can't place (#46),
// a parsed capture kept in Recent (#47), and notes it saves announced to the
// note lists (#48).

@Suite("Command bar names it can't place (Fix1011M)")
struct CommandBarUnplacedNamesFix1011MTests {
    private let sarahAdler = StudentData(id: UUID(), firstName: "Sarah", lastName: "Adler", nickname: nil)
    private let sarahBloom = StudentData(id: UUID(), firstName: "Sarah", lastName: "Bloom", nickname: nil)
    private let ettyDavis = StudentData(id: UUID(), firstName: "Etty", lastName: "Davis", nickname: nil)
    private let ettyKatz = StudentData(id: UUID(), firstName: "Etty", lastName: "Katz", nickname: nil)
    private let cube = LessonData(
        id: UUID(), name: "Binomial Cube", area: "Sensorial", sequence: "Algebraic Solids"
    )

    private var roster: [StudentData] { [sarahAdler, sarahBloom, ettyDavis, ettyKatz] }

    private func proposal(unresolved: [String], entries: [StudentCaptureProposal] = []) -> CaptureProposal {
        CaptureProposal(
            rawText: "I gave the binomial cube to Sarah and Etty.",
            recordsPresentation: true,
            lessonID: cube.id,
            lessonName: cube.name,
            groupObservation: "",
            studentEntries: entries,
            unresolvedStudentNames: unresolved,
            source: .deterministic
        )
    }

    @Test("Save stays off while a name is still unplaced")
    @MainActor
    func unplacedNameBlocksSave() throws {
        let viewModel = CommandBarViewModel()
        viewModel.captureProposal = proposal(
            unresolved: ["Sarah"],
            entries: [StudentCaptureProposal(studentID: ettyDavis.id, studentName: "Etty D")]
        )
        let message = try #require(viewModel.captureValidationMessage)
        #expect(message.contains("Sarah"))
    }

    @Test("Picking Etty D clears only the Etty warning; Sarah's stays")
    func pickingOneChildClearsOnlyHerName() {
        var capture = proposal(unresolved: ["Sarah", "Etty"])
        capture.setStudent(ettyDavis, named: "Etty D", isSelected: true)
        #expect(capture.unresolvedStudentNames == ["Sarah"])
        #expect(capture.studentIDs == [ettyDavis.id])

        // Taking a child off again doesn't make the other name go away either.
        capture.setStudent(ettyDavis, named: "Etty D", isSelected: false)
        #expect(capture.unresolvedStudentNames == ["Sarah"])

        capture.setStudent(sarahBloom, named: "Sarah B", isSelected: true)
        #expect(capture.unresolvedStudentNames.isEmpty)
    }

    @Test("Picking the child brings what was said about her name into her entry")
    func pickedChildTakesHerWords() throws {
        var capture = proposal(unresolved: ["Sarah"])
        capture.unplacedWords["Sarah"] = UnplacedStudentWords(
            observation: "Built the cube twice.", followUp: .practice, followUpDetail: "The cube again"
        )
        capture.setStudent(sarahBloom, named: "Sarah B", isSelected: true)

        let entry = try #require(capture.studentEntries.first)
        #expect(entry.studentID == sarahBloom.id)
        #expect(entry.observation == "Built the cube twice.")
        #expect(entry.followUp == .practice)
        #expect(entry.followUpDetail == "The cube again")
        #expect(capture.unplacedWords.isEmpty)
        #expect(capture.unresolvedStudentNames.isEmpty)
    }

    @Test("Leave Out takes the name away, and Save can go ahead")
    @MainActor
    func leaveOutLetsSaveGoAhead() {
        let viewModel = CommandBarViewModel()
        var capture = proposal(
            unresolved: ["Sarah"],
            entries: [StudentCaptureProposal(studentID: ettyDavis.id, studentName: "Etty D")]
        )
        capture.unplacedWords["Sarah"] = UnplacedStudentWords(observation: "Watched.")
        capture.leaveOutUnplacedName("Sarah")
        viewModel.captureProposal = capture

        #expect(capture.unresolvedStudentNames.isEmpty)
        #expect(capture.unplacedWords.isEmpty)
        #expect(viewModel.captureValidationMessage == nil)
    }

    @Test("A short name with a period, or a nickname, settles the name too")
    func shortNameAndNicknameSettle() {
        let nicknamed = StudentData(id: UUID(), firstName: "Elisheva", lastName: "Katz", nickname: "Ellie")
        #expect(CaptureProposal.name("Etty D.", couldMean: ettyDavis))
        #expect(CaptureProposal.name("etty davis", couldMean: ettyDavis))
        #expect(CaptureProposal.name("Ellie", couldMean: nicknamed))
        #expect(!CaptureProposal.name("Sarah", couldMean: ettyDavis))
        #expect(!CaptureProposal.name("Etty K", couldMean: ettyDavis))
    }

    @Test("The fallback organizer lists a first name two children share")
    func fallbackListsSharedFirstName() async throws {
        let input = "I gave the binomial cube to Sarah and Etty D"
        let result = await LocalCommandParser().parse(input: input, students: roster, lessons: [cube])
        let command: ParsedCommand
        switch result {
        case .parsed(let parsed): command = parsed
        case .ambiguous(let suggestions): command = try #require(suggestions.first)
        case .failed(let reason):
            Issue.record("Expected a parse, got \(reason)")
            return
        }
        #expect(command.studentIDs == [ettyDavis.id])

        let capture = CommandBarService.makeDeterministicProposal(input: input, command: command, students: roster)
        #expect(capture.unresolvedStudentNames == ["Sarah"])
        #expect(capture.studentIDs == [ettyDavis.id])
    }
}

@Suite("Command bar Recent and note announcements (Fix1011M)")
@MainActor
struct CommandBarRecentAndNotesFix1011MTests {
    /// Runs `body` with the Sample Class's Recent list emptied, then puts the
    /// list back, so the test leaves the simulator's own list as it found it.
    private func withEmptySampleRecent(_ body: (CommandBarViewModel) async throws -> Void) async rethrows {
        let viewModel = CommandBarViewModel()
        viewModel.isSampleClassroom = true
        let saved = viewModel.recentCommands
        viewModel.recentCommands = []
        defer { viewModel.recentCommands = saved }
        try await body(viewModel)
    }

    @Test("A capture that was organized is in Recent before it is saved")
    func parsedCaptureGoesToRecent() async {
        let maya = StudentData(id: UUID(), firstName: "Maya", lastName: "Levy", nickname: nil)
        let cube = LessonData(id: UUID(), name: "Binomial Cube", area: "Sensorial", sequence: "Algebraic Solids")
        let text = "I gave Maya the binomial cube. She built it twice."
        await withEmptySampleRecent { viewModel in
            viewModel.inputText = text
            await viewModel.submit(students: [maya], lessons: [cube])
            #expect(viewModel.captureProposal != nil)
            #expect(viewModel.recentCommands.first == text)
        }
    }

    @Test("Saving a capture announces its notes, so the note lists reload")
    func captureSaveAnnouncesNotes() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Levy")
        try context.save()
        let studentID = try #require(student.id)

        let announced = NoteDidSaveRecorder()
        defer { announced.stop() }

        try await withEmptySampleRecent { viewModel in
            viewModel.captureProposal = CaptureProposal(
                rawText: "Maya sorted every bead bar.",
                recordsPresentation: false,
                lessonID: nil,
                lessonName: nil,
                groupObservation: "",
                studentEntries: [StudentCaptureProposal(
                    studentID: studentID, studentName: "Maya L", observation: "Maya sorted every bead bar."
                )],
                unresolvedStudentNames: [],
                source: .deterministic
            )
            let saveCoordinator = SaveCoordinator()
            saveCoordinator.suppressAlerts = true
            _ = try viewModel.saveCaptureProposal(context: context, saveCoordinator: saveCoordinator)
        }

        let noteIDs = Set(try context.fetch(CDFetchRequest(CDNote.self)).compactMap(\.id))
        #expect(noteIDs.count == 1)
        #expect(announced.ids.contains { noteIDs.contains($0) })
    }
}

/// Collects the note ids `.noteDidSave` announces while it is alive. Other
/// tests may post at the same time, so a test looks for its own note's id
/// rather than counting.
final class NoteDidSaveRecorder: Sendable {
    private final class Received: Sendable {
        let ids = Mutex<[UUID]>([])
    }

    private let received: Received
    private let observer: Mutex<(any NSObjectProtocol)?>

    init() {
        let received = Received()
        self.received = received
        let token = NotificationCenter.default.addObserver(
            forName: .noteDidSave, object: nil, queue: nil
        ) { notification in
            guard let id = notification.object as? UUID else { return }
            received.ids.withLock { $0.append(id) }
        }
        observer = Mutex(token)
    }

    var ids: [UUID] { received.ids.withLock { $0 } }

    func stop() {
        observer.withLock { token in
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
    }
}
