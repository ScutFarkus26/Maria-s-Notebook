import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Domain logic Phase 10, from the docs pass: new project work carries its
// stamp when it is made (R22), the default kind follows a giving rather than
// a plan (R14), and mark_mastered says what it did to each row (R2, R23).

@Suite("Work made and closed (domain logic, Phase 10)")
@MainActor
struct FinalCheckWorkTests {

    // MARK: - R22: stamped when made

    @Test("New project work is stamped shared when made, so the launch fill has nothing to do")
    func newProjectWorkIsStampedShared() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let session = CDProjectSession(context: context)
        session.id = UUID()
        let service = SessionWorkAssignmentService(context: context)
        let adaID = try #require(ada.id).uuidString

        let offered = try service.createOfferedWork(session: session, title: "Poster", instructions: "", dueDate: nil)
        let uniform = try #require(try service.createUniformWork(
            session: session, studentID: adaID, lessonID: UUID(),
            title: "Map", instructions: "", scheduledDate: Date()
        ))

        #expect(offered.isSharedRow, "offered to the class, a row its children share")
        #expect(offered.assignmentID == offered.id?.uuidString, "its own assignment")
        #expect(uniform.isSharedRow, "project work is shared by construction, as the fill stamps it")
        #expect(CoreDataTestHelpers.save(context))
        #expect(WorkAssignmentFill.run(in: context) == 0, "the new rows already read as the fill would write them")
    }

    // MARK: - R14: the default kind

    @Test("Work on a lesson only planned for her is Follow-Up; once she's been given it, Practice")
    func defaultKindFollowsAGiving() throws {
        let room = try PresentingRoom.make()
        let lessonID = try #require(room.first.id)
        let plan = PresentationFactory.makeDraft(lesson: room.first, students: [room.ada], context: room.context)
        let repository = WorkRepository(context: room.context)

        let early = try repository.createWork(studentID: room.adaID, lessonID: lessonID, saveImmediately: false)

        #expect(early.kind == .followUpAssignment, "nothing given yet to practice")
        #expect(early.presentationID == plan.id?.uuidString, "it still follows the plan")

        let given = try room.given(room.first, to: [room.ada], on: "2026-10-05")
        let later = try repository.createWork(studentID: room.adaID, lessonID: lessonID, saveImmediately: false)

        #expect(later.kind == .practiceLesson)
        #expect(later.presentationID == given.id?.uuidString)
    }

    // MARK: - R2 and R23: what mark_mastered says

    @Test("mark_mastered says a shared row only finished her part, and closed as Finished with the last child")
    func markReplySaysWhatHappenedToEachRow() async throws {
        let room = try PresentingRoom.make()
        try room.given(room.first, to: [room.ada, room.ben], on: "2026-10-05")
        // A group row with no owner, both children on it.
        let shared = CoreDataTestHelpers.seedWorkModel(in: room.context, title: "Bead chains", lessonID: room.first.id!)
        shared.id = UUID()
        shared.studentID = ""
        for child in [room.adaID, room.benID] {
            let participant = CDWorkParticipantEntity(context: room.context)
            participant.id = UUID()
            participant.studentID = child.uuidString
            participant.work = shared
        }
        try room.context.save()

        let first = try await room.tool("mark_mastered").handler([
            "lesson": .string(room.first.name), "student_names": .array([.string("Ada")])
        ])

        #expect(first.contains("finished her part of a shared work item; it stays open for 1 classmate"))
        #expect(shared.status.isOpen)

        let second = try await room.tool("mark_mastered").handler([
            "lesson": .string(room.first.name), "student_names": .array([.string("Ben")])
        ])

        #expect(second.contains("closed the shared work item as Finished"))
        #expect(!second.contains("as Mastered"), "the shared row's verdict is Finished, not Mastered")
        #expect(shared.status == .done)
    }
}
