import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Domain logic fixes, Phase 4 (review 2026-11-20): R3, R6, R10, R12 and R24.
// Each test goes through the path a guide (or Claude) uses, so it reads the
// same on main, where it fails, and after the fix.

@Suite("Presenting records (domain logic Phase 4)")
@MainActor
struct PresentingRecordsTests {

    // MARK: - R3: the recap's pill on a lesson she never had

    @Test("A recap pill on a lesson she has no record of makes no \"given today\"")
    func recapPillOnUngivenLessonIsUndated() throws {
        let room = try PresentingRoom.make()
        let assignment = try room.given(room.first, to: [room.ada], on: "2026-10-05")
        try room.context.save()
        let viewModel = PresentationDetailViewModel(
            lessonAssignment: assignment, viewContext: room.context, saveCoordinator: room.coordinator
        )

        viewModel.updateSiblingLessonProficiencyState(
            lessonID: room.second.id!.uuidString, studentID: room.adaID.uuidString, state: .practicing,
            lessons: [room.first, room.second], currentLesson: room.first, students: [room.ada]
        )

        let rows = room.rows(room.ada, room.second)
        #expect(rows.count == 1)
        #expect(rows.first?.presentedAt == nil, "an undated mark, not today")
        let index = PresentationRecordIndex(lessonIDs: [room.second.id!.uuidString], in: room.context)
        let given = try #require(index.given(student: room.adaID.uuidString, lesson: room.second.id!.uuidString))
        #expect(given.days.isEmpty, "the record holds no day for it")
        let undated = room.assignments(room.second).filter { $0.isPresented && $0.presentedAt == nil }
        #expect(undated.count == 1, "she is on the undated presentation, as the Checklist attaches")
    }

    // MARK: - R6: Claude's decisions write her follow-up row

    @Test("Claude's Ready resolves her follow-up row, so she leaves Keep Watching")
    func claudesReadyWritesTheFollowUpRow() async throws {
        let room = try PresentingRoom.make()
        _ = try await room.tool("record_presentation").handler([
            "lesson": .string(room.first.name),
            "student_names": .array([.string("Ada"), .string("Ben")]),
            "student_observations": .array([
                .object(["student": .string("Ada"), "observation": .string("Ready to go on."),
                         "follow_up": .string("ready_for_next_lesson")]),
                .object(["student": .string("Ben"), "observation": .string("Needs more."),
                         "follow_up": .string("practice")])
            ])
        ])

        let ada = try #require(room.rows(room.ada, room.first).first)
        #expect(ada.followUpResolution == .readyForNextPresentation)
        #expect(ada.followUpResolvedAt != nil)
        let ben = try #require(room.rows(room.ben, room.first).first)
        #expect(ben.followUpAction == .checkWork, "practice is work to check, not Keep Watching")
    }

    // MARK: - R10: notes dated the day it was given

    @Test("Friday's notes recorded on Monday are dated Friday")
    func notesTakeThePresentationsDay() throws {
        let room = try PresentingRoom.make()
        let friday = try room.day("2026-11-13")
        let assignment = try room.given(room.first, to: [room.ada, room.ben], on: "2026-11-13")
        try room.context.save()

        try PresentationSessionCommit.apply(
            PresentationSessionCommit.Input(
                assignment: assignment, lesson: room.first, studentIDs: [room.adaID, room.benID],
                groupNote: "Both built 2,345.", childNotes: [room.adaID: "Carried without help."],
                decisions: [:], allDecisions: [:], checkIn: .nextWorkCycle, lessons: [room.first, room.second]
            ),
            context: room.context, saveCoordinator: room.coordinator
        )

        let notes = room.context.safeFetch(CDFetchRequest(CDNote.self))
        #expect(notes.count == 2)
        #expect(notes.allSatisfy { note in
            note.createdAt.map { AppCalendar.shared.isDate($0, inSameDayAs: friday) } ?? false
        })
    }

    // MARK: - R12: which presentation a lesson lands on

    @Test("Saving the same capture twice edits the one presentation")
    func commandBarSameDayIsAnEdit() throws {
        let room = try PresentingRoom.make()
        let viewModel = CommandBarViewModel()
        for _ in 0..<2 {
            viewModel.captureProposal = CaptureProposal(
                rawText: "I gave Ada the golden beads.", recordsPresentation: true,
                lessonID: room.first.id, lessonName: room.first.name, groupObservation: "",
                studentEntries: [StudentCaptureProposal(studentID: room.adaID, studentName: "Ada T")],
                unresolvedStudentNames: [], source: .deterministic
            )
            _ = try viewModel.saveCaptureProposal(context: room.context, saveCoordinator: room.coordinator)
        }

        #expect(room.assignments(room.first).filter(\.isPresented).count == 1)
        #expect(room.rows(room.ada, room.first).count == 1)
    }

    // MARK: - R24: per-child facts

    @Test("A child taken off a presentation and added back isn't confirmed")
    func takenOffAndBackIsNotConfirmed() throws {
        let room = try PresentingRoom.make()
        let assignment = PresentationFactory.makeDraft(
            lesson: room.first, students: [room.ada, room.ben], context: room.context
        )
        assignment.confirmStudent(room.benID)
        #expect(assignment.isStudentConfirmed(room.benID))

        assignment.studentIDs = [room.adaID.uuidString]
        assignment.studentIDs = [room.adaID.uuidString, room.benID.uuidString]

        #expect(!assignment.isStudentConfirmed(room.benID))
    }

    @Test("A confirmation stored in another spelling of her id survives a roster edit")
    func confirmationSpellingSurvives() throws {
        let room = try PresentingRoom.make()
        let assignment = PresentationFactory.makeDraft(
            lesson: room.first, students: [room.ada, room.ben], context: room.context
        )
        assignment.confirmedStudentIDs = [room.benID.uuidString.lowercased()]
        assignment.studentIDs = [room.adaID.uuidString, " " + room.benID.uuidString.lowercased()]
        #expect(assignment.confirmedStudentIDs == [room.benID.uuidString.lowercased()])
    }

    @Test("One child's needs-practice on a group presentation holds back only her")
    func needsPracticeIsPerChild() throws {
        let room = try PresentingRoom.make()
        let given = try room.given(room.first, to: [room.ada, room.ben], on: "2026-10-05")
        given.confirmStudent(room.adaID)
        given.confirmStudent(room.benID)
        // Ada's row says she needs practice; Ben's says he doesn't. The group
        // record says "any child", for older builds.
        room.rows(room.ada, room.first).first?.needsPractice = true
        room.rows(room.ben, room.first).first?.needsPractice = false
        given.needsPractice = true
        let plan = PresentationFactory.makeDraft(
            lesson: room.second, students: [room.ada, room.ben], context: room.context
        )
        try room.context.save()

        let result = BlockingAlgorithmEngine.checkBlocking(
            forBatch: [plan], lessons: [room.first, room.second],
            allLessonAssignments: room.assignments(room.first) + [plan],
            workModels: [], masteryMarks: [:]
        )[plan.id!]

        let readiness = try #require(result?.perStudentReadiness)
        #expect(readiness[room.benID]?.isReady == true, "Ben's own row says no practice is needed")
        #expect(readiness[room.adaID]?.isReady == false)
    }
}
