import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, Part 2 #77, #79, #80: the command bar's intent words and
// dictation.

@Suite("Command bar intent words (Fix1010J2b)")
struct CommandBarIntentWordsFix1010J2bTests {
    private let maya = StudentData(id: UUID(), firstName: "Maya", lastName: "Cohen", nickname: nil)
    private let cube = LessonData(
        id: UUID(), name: "Binomial Cube", area: "Sensorial", sequence: "Algebraic Solids"
    )

    private func parse(_ input: String) async -> ParsedCommand? {
        let result = await LocalCommandParser().parse(input: input, students: [maya], lessons: [cube])
        switch result {
        case .parsed(let command): return command
        case .ambiguous(let suggestions): return suggestions.first
        case .failed: return nil
        }
    }

    @Test("A presentation that ends with 'working on it' stays a presentation")
    func presentationWithWorkingOnLater() async throws {
        let command = try #require(await parse("I gave Maya the binomial cube, she'll keep working on it"))
        #expect(command.intent == .recordPresentation)
    }

    @Test("An observation that mentions working on something stays an observation")
    func observationWithWorkingOnLater() async throws {
        let command = try #require(await parse("Maya was so focused, I noticed she kept working on it"))
        #expect(command.intent == .addNote)
    }

    @Test("A sentence that leads with 'need to' is a todo, and the lead is taken off")
    func leadingNeedToIsTodo() async throws {
        let command = try #require(await parse("I need to email the office about the field trip"))
        #expect(command.intent == .addTodo)
        #expect(command.freeText == "email the office about the field trip")
    }

    @Test("The iPhone keyboard's curly apostrophe still reads as \"don't forget\"")
    func curlyApostropheDontForget() async throws {
        let command = try #require(await parse("Don’t forget the permission slips"))
        #expect(command.intent == .addTodo)
        #expect(command.freeText == "the permission slips")
    }

    @Test("A leading quick-form word still opens its form")
    func leadingAssignIsWork() async throws {
        let command = try #require(await parse("Assign Maya the binomial cube"))
        #expect(command.intent == .assignWork)
        #expect(command.freeText == "Maya the binomial cube")
    }

    @Test("Work words with no presentation or observation still mean work")
    func plainWorkSentence() async throws {
        let command = try #require(await parse("Maya is working on the binomial cube"))
        #expect(command.intent == .assignWork)
    }

    @Test("An intent word in the middle of the account isn't cut out of it")
    func midSentenceKeywordKept() async throws {
        let input = "Maya was so focused today, I noticed"
        let command = try #require(await parse(input))
        #expect(command.intent == .addNote)
        #expect(command.freeText == input)
    }

    @Test("A todo written after a name is a todo, not a presentation", arguments: [
        "Maya: need to show her the binomial cube",
        "Etty B – don’t forget to give her the map",
        "Maya, remind me to present the binomial cube"
    ])
    func todoAfterNameStaysTodo(input: String) async throws {
        let command = try #require(await parse(input))
        #expect(command.intent == .addTodo)
    }

    @Test("Punctuation doesn't hide an intent word")
    func punctuationAfterKeyword() async throws {
        let command = try #require(await parse("Presented, to Maya: the binomial cube"))
        #expect(command.intent == .recordPresentation)
    }

    @Test("The service sends a presentation that ends in 'working on it' to capture, not New Work")
    @MainActor
    func serviceRoutesPresentationToCapture() async {
        let service = CommandBarService()
        await service.parse(
            input: "I gave Maya the binomial cube, she'll keep working on it",
            students: [maya],
            lessons: [cube]
        )
        // The capture flow, whichever organizer made the proposal (Apple
        // Intelligence where the simulator has it, the local fallback where not).
        // Before the fix this was `.result` with the New Work intent.
        guard case .capture = service.parseState else {
            Issue.record("Expected the capture flow, got \(service.parseState)")
            return
        }
    }
}

@Suite("Dictation text and stops (Fix1010J2b)")
struct DictationFix1010J2bTests {
    @Test("Dictated words go after what was typed")
    func appendsAfterTyped() {
        #expect(SpeechRecognitionService.appending("she chose the red rods", to: "Maya:")
            == "Maya: she chose the red rods")
        #expect(SpeechRecognitionService.appending("again", to: "Maya worked ") == "Maya worked again")
        #expect(SpeechRecognitionService.appending("hello", to: "") == "hello")
        #expect(SpeechRecognitionService.appending("hello", to: "  ") == "hello")
        #expect(SpeechRecognitionService.appending("", to: "typed") == "typed")
    }

    @Test("A normal stop isn't reported as a failure")
    func normalStopsIgnored() {
        #expect(SpeechRecognitionService.isNormalStop(domain: "kLSRErrorDomain", code: 301))
        #expect(SpeechRecognitionService.isNormalStop(domain: "kAFAssistantErrorDomain", code: 1110))
        #expect(SpeechRecognitionService.isNormalStop(domain: "kAFAssistantErrorDomain", code: 216))
        #expect(!SpeechRecognitionService.isNormalStop(domain: "kAFAssistantErrorDomain", code: 1700))
        #expect(!SpeechRecognitionService.isNormalStop(domain: "kLSRErrorDomain", code: 102))
    }

    @Test("Before dictation starts, the field's text is the typed text")
    @MainActor
    func dictatedTextWithoutTranscript() {
        let service = SpeechRecognitionService()
        #expect(service.transcript.isEmpty)
        #expect(service.dictatedText.isEmpty)
    }
}

// Bug hunt 2026-10-10, Part 2 #90: captures were always dated now.

@Suite("Capture date from the guide's words (Fix1010J2b)")
struct CaptureDateFix1010J2bTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }()

    /// Saturday, October 10, 2026, mid-afternoon.
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 15)) ?? Date()
    }

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day)) ?? Date()
    }

    private func parsed(_ text: String) -> Date {
        CaptureDateParser.day(in: text, today: today, calendar: calendar)
    }

    @Test("Days she names in the last school week")
    func namedDays() {
        #expect(parsed("Yesterday I gave Maya the binomial cube") == day(10, 9))
        #expect(parsed("On Tuesday I showed Leah the map") == day(10, 6))
        #expect(parsed("Saturday I gave the stamp game to Ari") == day(10, 10))
        #expect(parsed("Last Saturday I gave the stamp game to Ari") == day(10, 3))
        #expect(parsed("On Oct 8th I presented the bead frame") == day(10, 8))
        #expect(parsed("I gave Maya the cube on 10/7") == day(10, 7))
        #expect(parsed("This morning I gave Maya the cube") == day(10, 10))
    }

    @Test("No day, a day still to come, or one too long ago means today")
    func fallsBackToToday() {
        #expect(parsed("I gave Maya the binomial cube") == day(10, 10))
        #expect(parsed("On Oct 12 I gave Maya the cube") == day(10, 10))
        #expect(parsed("On September 1 I gave Maya the cube") == day(10, 10))
        #expect(parsed("Maya 2 times repeated the cube") == day(10, 10))
        #expect(parsed("She counted 3/4 of the beads") == day(10, 10))
    }

    @Test("Today keeps the time of day; an earlier day is its start")
    func momentForDay() {
        let now = today
        #expect(CaptureDateParser.moment(on: day(10, 10), now: now, calendar: calendar) == now)
        #expect(CaptureDateParser.moment(on: day(10, 9), now: now, calendar: calendar) == day(10, 9))
    }

    @MainActor
    private func save(_ proposal: CaptureProposal, in context: NSManagedObjectContext) throws -> CaptureSaveReceipt {
        let viewModel = CommandBarViewModel()
        viewModel.captureProposal = proposal
        let saveCoordinator = SaveCoordinator()
        saveCoordinator.suppressAlerts = true
        return try viewModel.saveCaptureProposal(context: context, saveCoordinator: saveCoordinator)
    }

    @Test("A presentation captured today keeps the time it was saved")
    @MainActor
    func todayKeepsTime() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Levy")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        try context.save()
        let studentID = try #require(student.id)
        let before = Date()

        let receipt = try save(CaptureProposal(
            rawText: "I gave Maya the stamp game.",
            recordsPresentation: true,
            lessonID: lesson.id,
            lessonName: lesson.name,
            groupObservation: "",
            studentEntries: [StudentCaptureProposal(studentID: studentID, studentName: "Maya Levy")],
            unresolvedStudentNames: [],
            source: .deterministic
        ), in: context)

        let presentationID = try #require(receipt.presentationID)
        let assignment = try #require(context.object(CDLessonAssignment.self, id: presentationID))
        let presentedAt = try #require(assignment.presentedAt)
        #expect(presentedAt >= before.addingTimeInterval(-1))
    }

    @Test("An observation-only capture about yesterday is dated yesterday")
    @MainActor
    func observationOnlyDatedOnDay() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Levy")
        try context.save()
        let studentID = try #require(student.id)
        let yesterday = AppCalendar.addingDays(-1, to: AppCalendar.startOfDay(Date()))

        let receipt = try save(CaptureProposal(
            rawText: "Yesterday Maya sorted every bead bar.",
            recordsPresentation: false,
            lessonID: nil,
            lessonName: nil,
            groupObservation: "",
            studentEntries: [StudentCaptureProposal(
                studentID: studentID, studentName: "Maya Levy", observation: "Maya sorted every bead bar."
            )],
            unresolvedStudentNames: [],
            source: .deterministic,
            presentedOn: yesterday
        ), in: context)

        #expect(receipt.noteCount == 1)
        let note = try #require(try context.fetch(CDFetchRequest(CDNote.self)).first {
            $0.body == "Maya sorted every bead bar."
        })
        #expect(note.createdAt == yesterday)
    }

    @Test("A presentation is saved on the proposal's day, at the start of that day")
    @MainActor
    func savedOnProposalDay() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Levy")
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game", area: "Mathematics", sequence: "Decimal System"
        )
        try context.save()
        let studentID = try #require(student.id)
        let lessonID = try #require(lesson.id)
        let yesterday = AppCalendar.addingDays(-1, to: AppCalendar.startOfDay(Date()))

        let receipt = try save(CaptureProposal(
            rawText: "Yesterday I gave Maya the stamp game. She exchanged tens.",
            recordsPresentation: true,
            lessonID: lessonID,
            lessonName: lesson.name,
            groupObservation: "",
            studentEntries: [
                StudentCaptureProposal(
                    studentID: studentID, studentName: "Maya Levy", observation: "She exchanged tens."
                )
            ],
            unresolvedStudentNames: [],
            source: .deterministic,
            presentedOn: yesterday
        ), in: context)

        let presentationID = try #require(receipt.presentationID)
        let assignment = try #require(context.object(CDLessonAssignment.self, id: presentationID))
        #expect(assignment.presentedAt == yesterday)
        let note = try #require(try context.fetch(CDFetchRequest(CDNote.self)).first {
            $0.body == "She exchanged tens."
        })
        #expect(note.createdAt == yesterday)
    }
}
