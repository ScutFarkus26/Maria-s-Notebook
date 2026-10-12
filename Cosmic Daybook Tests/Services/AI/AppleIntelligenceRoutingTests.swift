import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Apple Intelligence Routing")
struct AppleIntelligenceRoutingTests {
    @Test("Automatic Private Cloud use is opt-in")
    func automaticPrivateCloudDefaultsOff() {
        let key = UserDefaultsKeys.aiAllowAutomaticPrivateCloud
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(!AIClientRouter.automaticPrivateCloudAllowed)
        UserDefaults.standard.set(true, forKey: key)
        #expect(AIClientRouter.automaticPrivateCloudAllowed)
    }
}

@Suite("Capture What Happened Proposals")
@MainActor
struct CaptureProposalTests {
    @Test("Deterministic presentation fallback never invents a next step")
    func deterministicPresentationHasNoInferredFollowUp() {
        let studentID = UUID()
        let lessonID = UUID()
        let students = [
            StudentData(id: studentID, firstName: "Sarah", lastName: "Cohen", nickname: nil)
        ]
        let command = ParsedCommand(
            intent: .recordPresentation,
            studentIDs: [studentID],
            lessonID: lessonID,
            rawStudentNames: ["Sarah Cohen"],
            rawLessonName: "Binomial Cube",
            freeText: "Sarah completed it twice and seemed ready",
            inferredTags: [],
            confidence: 0.8
        )

        let proposal = CommandBarService.makeDeterministicProposal(
            input: "I gave Sarah the binomial cube. She completed it twice and seemed ready.",
            command: command,
            students: students
        )

        #expect(proposal.recordsPresentation)
        #expect(proposal.lessonID == lessonID)
        #expect(proposal.studentEntries.count == 1)
        #expect(proposal.studentEntries[0].followUp == .none)
        #expect(proposal.studentEntries[0].observation == "She completed it twice and seemed ready.")
    }

    @Test("A one-child note remains editable for that child")
    func singleStudentObservationFallsIntoStudentEntry() {
        let studentID = UUID()
        let students = [
            StudentData(id: studentID, firstName: "Leah", lastName: "Levy", nickname: nil)
        ]
        let command = ParsedCommand(
            intent: .addNote,
            studentIDs: [studentID],
            lessonID: nil,
            rawStudentNames: ["Leah Levy"],
            rawLessonName: nil,
            freeText: "Leah returned every piece to the tray",
            inferredTags: [],
            confidence: 0.7
        )

        let proposal = CommandBarService.makeDeterministicProposal(
            input: "I noticed Leah returned every piece to the tray",
            command: command,
            students: students
        )

        #expect(!proposal.recordsPresentation)
        #expect(proposal.groupObservation.isEmpty)
        #expect(proposal.studentEntries[0].observation == "Leah returned every piece to the tray")
        #expect(proposal.studentEntries[0].followUp == .none)
    }

    @Test("Deterministic fallback does not mis-scope a group account")
    func groupFallbackKeepsUnseparatedWordsForReview() {
        let firstID = UUID()
        let secondID = UUID()
        let students = [
            StudentData(id: firstID, firstName: "Ari", lastName: "Cohen", nickname: nil),
            StudentData(id: secondID, firstName: "Bina", lastName: "Levy", nickname: nil)
        ]
        let command = ParsedCommand(
            intent: .recordPresentation,
            studentIDs: [firstID, secondID],
            lessonID: UUID(),
            rawStudentNames: ["Ari Cohen", "Bina Levy"],
            rawLessonName: "Golden Beads",
            freeText: "Ari worked independently; Bina asked to repeat the exchange.",
            inferredTags: [],
            confidence: 0.8
        )

        let proposal = CommandBarService.makeDeterministicProposal(
            input: "I gave Golden Beads to Ari and Bina. Ari worked independently; Bina asked to repeat the exchange.",
            command: command,
            students: students
        )

        #expect(proposal.groupObservation.isEmpty)
        #expect(proposal.studentEntries.allSatisfy { $0.observation.isEmpty })
        #expect(proposal.studentEntries.allSatisfy { $0.followUp == .none })
    }

    @Test("The review blocks presentation saving until lesson and children are resolved")
    func reviewRequiresPresentationIdentity() {
        let viewModel = CommandBarViewModel()
        viewModel.captureProposal = CaptureProposal(
            rawText: "I gave the lesson",
            recordsPresentation: true,
            lessonID: nil,
            lessonName: nil,
            groupObservation: "",
            studentEntries: [],
            unresolvedStudentNames: [],
            source: .deterministic
        )

        #expect(viewModel.captureValidationMessage == "Choose the lesson that was given.")
    }

    @Test("Confirmed composite save links notes and work to the exact repeat presentation")
    func confirmedSaveUsesExactPresentationIdentity() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(
            in: context,
            firstName: "Maya",
            lastName: "Levy"
        )
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context,
            name: "Stamp Game",
            area: "Mathematics",
            sequence: "Decimal System"
        )
        let studentID = try #require(student.id)
        let lessonID = try #require(lesson.id)
        let earlier = PresentationFactory.makePresented(
            lessonID: lessonID,
            studentIDs: [studentID],
            presentedAt: Date().addingTimeInterval(-86_400),
            context: context
        )
        try context.save()

        let viewModel = CommandBarViewModel()
        viewModel.captureProposal = CaptureProposal(
            rawText: "I presented stamp game to Maya. She exchanged tens independently. Offer more practice.",
            recordsPresentation: true,
            lessonID: lessonID,
            lessonName: lesson.name,
            groupObservation: "",
            studentEntries: [
                StudentCaptureProposal(
                    studentID: studentID,
                    studentName: "Maya Levy",
                    observation: "She exchanged tens independently.",
                    followUp: .practice,
                    followUpDetail: "Repeat two exchanges"
                )
            ],
            unresolvedStudentNames: [],
            source: .deterministic
        )
        let saveCoordinator = SaveCoordinator()
        saveCoordinator.suppressAlerts = true

        let receipt = try viewModel.saveCaptureProposal(
            context: context,
            saveCoordinator: saveCoordinator,
            presentedAt: Date()
        )
        let presentationID = try #require(receipt.presentationID)

        #expect(presentationID != earlier.id)
        #expect(receipt.noteCount == 1)
        #expect(receipt.workCount == 1)

        let workRequest = CDFetchRequest(CDWorkModel.self)
        let work = try #require(try context.fetch(workRequest).first {
            $0.studentID == studentID.uuidString && $0.lessonID == lessonID.uuidString
        })
        #expect(work.presentationID == presentationID.uuidString)

        let noteRequest = CDFetchRequest(CDNote.self)
        let note = try #require(try context.fetch(noteRequest).first {
            $0.body == "She exchanged tens independently."
        })
        #expect(note.lessonAssignment?.id == presentationID)
    }

    @Test("Duplicate synced student rows do not block saving reviewed details")
    func duplicateStudentRowsAreDeduplicatedForSaving() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(
            in: context,
            firstName: "Ari",
            lastName: "Cohen"
        )
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context,
            name: "Golden Beads",
            area: "Mathematics",
            sequence: "Decimal System"
        )
        let studentID = try #require(student.id)
        let lessonID = try #require(lesson.id)

        let duplicate = CDStudent(context: context)
        duplicate.id = studentID
        duplicate.firstName = student.firstName
        duplicate.lastName = student.lastName
        try context.save()

        let viewModel = CommandBarViewModel()
        viewModel.captureProposal = CaptureProposal(
            rawText: "Ari completed the exchange independently.",
            recordsPresentation: true,
            lessonID: lessonID,
            lessonName: lesson.name,
            groupObservation: "",
            studentEntries: [
                StudentCaptureProposal(
                    studentID: studentID,
                    studentName: "Ari Cohen",
                    observation: "Ari completed the exchange independently."
                )
            ],
            unresolvedStudentNames: [],
            source: .deterministic
        )
        let saveCoordinator = SaveCoordinator()
        saveCoordinator.suppressAlerts = true

        let receipt = try viewModel.saveCaptureProposal(
            context: context,
            saveCoordinator: saveCoordinator
        )

        #expect(receipt.presentationID != nil)
        #expect(receipt.noteCount == 1)
    }

    @Test("A failed reviewed save rolls back only its presentation, notes and follow-up work")
    func failedReviewedSaveIsAtomic() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let student = CoreDataTestHelpers.seedStudent(
            in: context,
            firstName: "Rina",
            lastName: "Cohen"
        )
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context,
            name: "Stamp Game",
            area: "Mathematics",
            sequence: "Decimal System"
        )
        let studentID = try #require(student.id)
        let lessonID = try #require(lesson.id)
        try context.save()

        // This unrelated invalid edit makes the eventual context save fail. It
        // must remain in place while this capture attempt rolls back only its own
        // newly-created note and work record.
        let invalidUnrelatedStudent = CDStudent(context: context)
        invalidUnrelatedStudent.setValue(nil, forKey: "firstName")

        let viewModel = CommandBarViewModel()
        viewModel.captureProposal = CaptureProposal(
            rawText: "Rina exchanged independently. Offer another practice.",
            recordsPresentation: true,
            lessonID: lessonID,
            lessonName: lesson.name,
            groupObservation: "Rina remained engaged throughout.",
            studentEntries: [
                StudentCaptureProposal(
                    studentID: studentID,
                    studentName: "Rina Cohen",
                    observation: "Rina exchanged independently.",
                    followUp: .practice,
                    followUpDetail: "Repeat with a new quantity"
                )
            ],
            unresolvedStudentNames: [],
            source: .deterministic
        )
        let saveCoordinator = SaveCoordinator()
        saveCoordinator.suppressAlerts = true

        do {
            _ = try viewModel.saveCaptureProposal(
                context: context,
                saveCoordinator: saveCoordinator
            )
            Issue.record("The reviewed save should fail when the context cannot save.")
        } catch let error as CaptureSaveError {
            guard case .saveFailed = error else {
                Issue.record("Expected saveFailed, received \(error)")
                return
            }
        }

        let noteRequest = CDFetchRequest(CDNote.self)
        let workRequest = CDFetchRequest(CDWorkModel.self)
        let presentationRequest = CDFetchRequest(CDLessonAssignment.self)
        #expect(try context.count(for: noteRequest) == 0)
        #expect(try context.count(for: workRequest) == 0)
        #expect(try context.count(for: presentationRequest) == 0)
        #expect(invalidUnrelatedStudent.isInserted)
        #expect(invalidUnrelatedStudent.value(forKey: "firstName") == nil)
    }
}
