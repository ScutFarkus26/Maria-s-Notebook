import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11 review (b), fix agent B2: the dictation grace period
// (#1), the fallback organizer with a name it couldn't place (#3), and a
// name that matches nobody (#4).

@Suite("Command bar fallback with an unplaced name (10-11 review B2)")
struct CommandBarFallbackUnplacedFix1011ReviewB2Tests {
    private let maya = StudentData(id: UUID(), firstName: "Maya", lastName: "Levy", nickname: nil)
    private let sarahAdler = StudentData(id: UUID(), firstName: "Sarah", lastName: "Adler", nickname: nil)
    private let sarahBloom = StudentData(id: UUID(), firstName: "Sarah", lastName: "Bloom", nickname: nil)

    private var roster: [StudentData] { [maya, sarahAdler, sarahBloom] }

    private func command(_ intent: RecordIntent, freeText: String) -> ParsedCommand {
        ParsedCommand(
            intent: intent,
            studentIDs: [maya.id],
            lessonID: intent == .recordPresentation ? UUID() : nil,
            rawStudentNames: ["Maya Levy"],
            rawLessonName: intent == .recordPresentation ? "Binomial Cube" : nil,
            freeText: freeText,
            inferredTags: [],
            confidence: 0.8,
            unresolvedStudentNames: ["Sarah"]
        )
    }

    @Test("A note about Maya and an unplaced Sarah is kept for the group, not given to Maya")
    func noteWithUnplacedNameStaysWithTheGroup() throws {
        let said = "Maya and Sarah built the cube"
        let capture = CommandBarService.makeDeterministicProposal(
            input: said, command: command(.addNote, freeText: said), students: roster
        )

        let entry = try #require(capture.studentEntries.first)
        #expect(capture.studentIDs == [maya.id])
        #expect(entry.observation.isEmpty)
        #expect(capture.groupObservation == said)
        #expect(capture.unresolvedStudentNames == ["Sarah"])
    }

    @Test("A presentation to Maya and an unplaced Sarah doesn't give Maya what was said about both")
    func presentationWithUnplacedNameIsNotMayasAlone() throws {
        let said = "I gave the binomial cube to Maya and Sarah. They built it twice."
        let capture = CommandBarService.makeDeterministicProposal(
            input: said, command: command(.recordPresentation, freeText: "They built it twice."), students: roster
        )

        let entry = try #require(capture.studentEntries.first)
        #expect(entry.observation.isEmpty)
        #expect(capture.unresolvedStudentNames == ["Sarah"])
    }

    @Test("A note about only an unplaced Sarah waits with her name and goes to the Sarah picked")
    func noteAboutOnlyAnUnplacedNameWaitsForThePick() throws {
        let said = "Sarah built the cube"
        let command = ParsedCommand(
            intent: .addNote, studentIDs: [], lessonID: nil, rawStudentNames: [], rawLessonName: nil,
            freeText: said, inferredTags: [], confidence: 0.7, unresolvedStudentNames: ["Sarah"]
        )
        var capture = CommandBarService.makeDeterministicProposal(input: said, command: command, students: roster)
        #expect(capture.studentEntries.isEmpty)
        #expect(capture.groupObservation.isEmpty)
        #expect(capture.unplacedWords["Sarah"]?.observation == said)

        capture.setStudent(sarahBloom, named: "Sarah B", isSelected: true)
        let entry = try #require(capture.studentEntries.first)
        #expect(entry.studentID == sarahBloom.id)
        #expect(entry.observation == said)
    }
}

@Suite("Command bar dictation's last words (10-11 review B2)")
@MainActor
struct CommandBarDictationFinishFix1011ReviewB2Tests {
    private let maya = StudentData(id: UUID(), firstName: "Maya", lastName: "Levy", nickname: nil)
    private let cube = LessonData(id: UUID(), name: "Binomial Cube", area: "Sensorial", sequence: "Algebraic Solids")

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

    /// Lets the tasks already started run up to their next wait.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("What she types after stopping dictation isn't wiped by the late last words")
    func typingAfterStopSurvivesTheLastWords() async {
        let viewModel = CommandBarViewModel()
        let speech = viewModel.speechService
        let session = speech.simulateRecording(appendingTo: "")
        speech.simulateResult("I gave the cube to Maya", isFinal: false, session: session)
        #expect(viewModel.inputText == "I gave the cube to Maya")

        // She taps the mic to stop; Speech is still finishing her words.
        let stop = Task { await speech.finishRecording() }
        while !speech.isFinishing { await Task.yield() }
        #expect(!speech.isRecording)

        viewModel.inputText += ", twice"
        speech.simulateResult("I gave the cube to Maya.", isFinal: true, session: session)
        await stop.value

        #expect(viewModel.inputText == "I gave the cube to Maya, twice")
        #expect(!speech.isFinishing)
    }

    @Test("Without typing, the last words still reach the field after she stops")
    func lastWordsLandWhenUntouched() async {
        let viewModel = CommandBarViewModel()
        viewModel.inputText = "Today:"
        let speech = viewModel.speechService
        let session = speech.simulateRecording(appendingTo: viewModel.inputText)
        speech.simulateResult("Maya built", isFinal: false, session: session)
        #expect(viewModel.inputText == "Today: Maya built")

        let stop = Task { await speech.finishRecording() }
        while !speech.isFinishing { await Task.yield() }
        speech.simulateResult("Maya built the cube twice", isFinal: true, session: session)
        await stop.value

        #expect(viewModel.inputText == "Today: Maya built the cube twice")
    }

    @Test("Send while dictation finishes waits for the last words, and a second Return doesn't send again")
    func sendDuringGraceWaitsAndSendsOnce() async {
        let partial = "I gave Maya the binomial cube"
        let final = "I gave Maya the binomial cube. She built it twice."
        await withEmptySampleRecent { viewModel in
            let speech = viewModel.speechService
            let session = speech.simulateRecording(appendingTo: "")
            speech.simulateResult(partial, isFinal: false, session: session)

            let stop = Task { await speech.finishRecording() }
            while !speech.isFinishing { await Task.yield() }

            // Return, then Return again, while the last words are on their way.
            let first = Task { await viewModel.send(students: [maya], lessons: [cube]) }
            let second = Task { await viewModel.send(students: [maya], lessons: [cube]) }
            await settle()
            #expect(viewModel.captureProposal == nil)
            #expect(viewModel.recentCommands.isEmpty)

            speech.simulateResult(final, isFinal: true, session: session)
            await first.value
            await second.value
            await stop.value

            #expect(viewModel.captureProposal != nil)
            #expect(viewModel.recentCommands == [final])
        }
    }

    @Test("Send while still recording finishes the dictation first and sends its last words")
    func sendWhileRecordingSendsTheLastWords() async {
        let final = "I gave Maya the binomial cube. She built it twice."
        await withEmptySampleRecent { viewModel in
            let speech = viewModel.speechService
            let session = speech.simulateRecording(appendingTo: "")
            speech.simulateResult("I gave Maya the binomial", isFinal: false, session: session)

            let send = Task { await viewModel.send(students: [maya], lessons: [cube]) }
            while !speech.isFinishing { await Task.yield() }
            speech.simulateResult(final, isFinal: true, session: session)
            await send.value

            #expect(viewModel.recentCommands == [final])
        }
    }
}

@Suite("Command bar name that matches nobody (10-11 review B2)")
struct CommandBarUnmatchedNameFix1011ReviewB2Tests {
    private let maya = StudentData(id: UUID(), firstName: "Maya", lastName: "Levy", nickname: nil)
    private let eli = StudentData(id: UUID(), firstName: "Eli", lastName: "Stern", nickname: nil)

    private func proposal(unresolved: [String]) -> CaptureProposal {
        var capture = CaptureProposal(
            rawText: "Maya and Eddie built the chain.",
            recordsPresentation: false,
            lessonID: nil,
            lessonName: nil,
            groupObservation: "",
            studentEntries: [StudentCaptureProposal(studentID: maya.id, studentName: "Maya L")],
            unresolvedStudentNames: unresolved,
            source: .appleIntelligence
        )
        for name in unresolved {
            capture.unplacedWords[name] = UnplacedStudentWords(observation: "Built the chain.")
        }
        return capture
    }

    @Test("A misheard name that matches nobody is settled by choosing its child, who gets its words")
    func chooseSettlesTheUnmatchedName() throws {
        var capture = proposal(unresolved: ["Eddie"])
        capture.placeUnplacedName("Eddie", on: eli, named: "Eli S")

        #expect(capture.unresolvedStudentNames.isEmpty)
        #expect(capture.unplacedWords.isEmpty)
        let entry = try #require(capture.studentEntries.first { $0.studentID == eli.id })
        #expect(entry.observation == "Built the chain.")
    }

    // Bug hunt 2026-10-29, #18: adding a child with Edit, with one misheard
    // name left, gave her its words and follow-up.
    @Test("Adding a child with Edit leaves a misheard name and what was said about it alone")
    func addingAChildDoesNotTakeAnUnmatchedName() throws {
        var capture = proposal(unresolved: ["Eddie"])
        capture.unplacedWords["Eddie"]?.followUp = .practice
        capture.setStudent(eli, named: "Eli S", isSelected: true)

        #expect(capture.unresolvedStudentNames == ["Eddie"])
        #expect(capture.unplacedWords["Eddie"]?.observation == "Built the chain.")
        let entry = try #require(capture.studentEntries.first { $0.studentID == eli.id })
        #expect(entry.observation.isEmpty)
        #expect(entry.followUp == .none)
    }

    @Test("Choosing a child already listed for a misheard name adds its words to hers")
    func chooseAListedChild() throws {
        var capture = proposal(unresolved: ["Eddie"])
        capture.studentEntries[0].observation = "Counted the links."
        capture.placeUnplacedName("Eddie", on: maya, named: "Maya L")

        #expect(capture.unresolvedStudentNames.isEmpty)
        #expect(capture.studentEntries.count == 1)
        #expect(capture.studentEntries[0].observation == "Counted the links. Built the chain.")
    }

    @Test("A shared first name isn't settled by picking a child it can't be")
    func sharedNameNeedsItsOwnChild() {
        var capture = proposal(unresolved: ["Sarah"])
        capture.setStudent(eli, named: "Eli S", isSelected: true)
        #expect(capture.unresolvedStudentNames == ["Sarah"])
        #expect(capture.unplacedWords["Sarah"] != nil)
    }

    @Test("With two names that match nobody, choosing one settles only that one")
    func twoUnmatchedNamesSettleOneAtATime() {
        var capture = proposal(unresolved: ["Eddie", "Zev"])
        capture.setStudent(eli, named: "Eli S", isSelected: true)
        #expect(capture.unresolvedStudentNames == ["Eddie", "Zev"])
        capture.placeUnplacedName("Zev", on: eli, named: "Eli S")
        #expect(capture.unresolvedStudentNames == ["Eddie"])
        #expect(capture.unplacedWords["Eddie"] != nil)
    }
}
