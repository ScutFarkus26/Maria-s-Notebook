import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The one readiness rule (Simplify the app, Phase 3): Ready; Ready, check
/// first, with a plain reason for each thing to check; Not ready yet. And the
/// previous-lesson status it reads, as the engine builds it from the store.
@Suite("Readiness rule")
@MainActor
struct ReadinessRuleTests {

    // MARK: - The rule itself

    private func status(
        confirmed: Bool = true,
        mastered: Bool = false,
        openWork: Int = 0,
        lastCheckIn: WorkStatus? = nil,
        recall: PreviousLessonStatus.Recall? = nil
    ) -> PreviousLessonStatus {
        PreviousLessonStatus(
            lessonID: "lesson", lastGiven: nil, confirmed: confirmed, mastered: mastered,
            openWorkCount: openWork, lastCheckIn: lastCheckIn, lastRecall: recall
        )
    }

    @Test("Confirmed, nothing open, no practice asked: Ready, with no reasons")
    func confirmedIsReady() {
        let verdict = ReadyForNextEngine.readiness(of: status())
        #expect(verdict.tier == .ready)
        #expect(verdict.reasons.isEmpty)
    }

    @Test("A mastery mark alone is Ready; a closed check-in that wasn't practice keeps her Ready")
    func masteredIsReady() {
        #expect(ReadyForNextEngine.readiness(of: status(confirmed: false, mastered: true)).tier == .ready)
        #expect(ReadyForNextEngine.readiness(of: status(lastCheckIn: .done)).tier == .ready)
        #expect(ReadyForNextEngine.readiness(of: status(lastCheckIn: .mastered)).tier == .ready)
        #expect(ReadyForNextEngine.readiness(of: status(recall: .retained)).tier == .ready)
    }

    @Test("Given but neither confirmed nor mastered: Not ready yet, whatever else holds")
    func unconfirmedIsNotReady() {
        let bare = ReadyForNextEngine.readiness(of: status(confirmed: false))
        #expect(bare.tier == .notReady)
        #expect(bare.reasons == ["Not confirmed yet"])
        // Finished work doesn't stand in for the guide's confirmation.
        #expect(ReadyForNextEngine.readiness(of: status(confirmed: false, lastCheckIn: .done)).tier == .notReady)
    }

    @Test("Open work: Ready, check first, singular and plural")
    func openWorkReason() {
        let one = ReadyForNextEngine.readiness(of: status(openWork: 1))
        #expect(one.tier == .almostReady)
        #expect(one.reasons == ["1 piece of work still open"])

        let two = ReadyForNextEngine.readiness(of: status(openWork: 2))
        #expect(two.tier == .almostReady)
        #expect(two.reasons == ["2 pieces of work still open"])
    }

    @Test("The last check-in asked for more practice: Ready, check first")
    func practiceAskedReason() {
        let verdict = ReadyForNextEngine.readiness(of: status(lastCheckIn: .keepPracticing))
        #expect(verdict.tier == .almostReady)
        #expect(verdict.reasons == ["Last check-in: needs more practice"])
    }

    @Test("The last recall check was shaky: Ready, check first")
    func shakyRecallReason() {
        let verdict = ReadyForNextEngine.readiness(of: status(recall: .shaky))
        #expect(verdict.tier == .almostReady)
        #expect(verdict.reasons == ["Recall check was shaky"])
    }

    @Test("Even a mastered lesson is Ready, check first while its work is open")
    func masteredWithOpenWork() {
        let verdict = ReadyForNextEngine.readiness(of: status(confirmed: false, mastered: true, openWork: 1))
        #expect(verdict.tier == .almostReady)
        #expect(verdict.reasons == ["1 piece of work still open"])
    }

    @Test("Every reason is listed, in one order")
    func everyReasonListed() {
        let verdict = ReadyForNextEngine.readiness(
            of: status(openWork: 3, lastCheckIn: .keepPracticing, recall: .shaky)
        )
        #expect(verdict.reasons == [
            "3 pieces of work still open", "Last check-in: needs more practice", "Recall check was shaky"
        ])
    }

    @Test("The previous lesson's line: given, open work, last check-in, mastered or not")
    func summaryLine() throws {
        let given = try CoreDataTestHelpers.day("2026-10-03")
        let previous = PreviousLessonStatus(
            lessonID: "lesson", lastGiven: given, confirmed: true, mastered: false,
            openWorkCount: 2, lastCheckIn: .keepPracticing
        )
        let date = given.formatted(.dateTime.month(.abbreviated).day())
        #expect(previous.summary
            == "Given \(date) · 2 pieces of work open · Last check-in: Keep Practicing · Not mastered yet")

        let mastered = PreviousLessonStatus(lessonID: "lesson", lastGiven: nil, mastered: true, openWorkCount: 1)
        #expect(mastered.summary == "Given, no date · 1 piece of work open · Mastered")
    }

    // MARK: - From the store

    private struct Room {
        let context: NSManagedObjectContext
        let first: CDLesson
        let second: CDLesson
        let maya: CDStudent
        let eli: CDStudent
    }

    private func makeRoom() throws -> Room {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CoreDataTestHelpers.seedLesson(
            in: context, name: "Commutative Law", area: "Math", sequence: "Laws"
        )
        first.orderInSequence = 10
        let second = CoreDataTestHelpers.seedLesson(
            in: context, name: "Distributive Law", area: "Math", sequence: "Laws"
        )
        second.orderInSequence = 20
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Park")
        return Room(context: context, first: first, second: second, maya: maya, eli: eli)
    }

    @discardableResult
    private func give(
        _ students: [CDStudent], _ lesson: CDLesson, on day: String, confirm: Bool, in room: Room
    ) throws -> CDLessonAssignment {
        let given = PresentationFactory.makePresented(
            lesson: lesson, students: students, presentedAt: try CoreDataTestHelpers.day(day),
            context: room.context
        )
        if confirm {
            for student in students { given.confirmStudent(try #require(student.id)) }
        }
        return given
    }

    private func work(
        _ student: CDStudent, on lesson: CDLesson, _ status: WorkStatus, closed: String? = nil, in room: Room
    ) throws {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: room.context, studentID: try #require(student.id), lessonID: try #require(lesson.id)
        )
        work.status = status
        if let closed { work.completedAt = try CoreDataTestHelpers.day(closed) }
    }

    private func recall(
        _ student: CDStudent, on lesson: CDLesson, _ outcome: RecallOutcome, on day: String,
        source: RecallSource = .observed, in room: Room
    ) throws {
        let check = CDLessonRecallCheck(context: room.context)
        check.studentID = try #require(student.id).uuidString
        check.lessonID = try #require(lesson.id).uuidString
        check.outcome = outcome
        check.source = source
        check.checkedAt = try CoreDataTestHelpers.day(day)
    }

    /// The queue's item for `student` on the second lesson.
    private func item(_ student: CDStudent, in room: Room) throws -> ReadyForNextItem? {
        #expect(CoreDataTestHelpers.save(room.context))
        let ids = try [room.maya, room.eli].map { try #require($0.id).uuidString }
        let index = PresentationRecordIndex(students: Set(ids), in: room.context)
        let items = ReadyForNextEngine.items(
            studentIDs: ids, lessons: [room.first, room.second], index: index, in: room.context
        )
        let studentID = try #require(student.id).uuidString
        return items.first { $0.studentID == studentID }
    }

    @Test("Two open pieces of her own work: the plural reason, and the count on the status")
    func twoOpenPieces() throws {
        let room = try makeRoom()
        try give([room.maya], room.first, on: "2026-10-01", confirm: true, in: room)
        try work(room.maya, on: room.first, .active, in: room)
        try work(room.maya, on: room.first, .review, in: room)

        let found = try #require(try item(room.maya, in: room))
        #expect(found.tier == .almostReady)
        #expect(found.reasons == ["2 pieces of work still open"])
        #expect(found.previous.openWorkCount == 2)
    }

    @Test("Her last check-in is the latest closed work: Keep Practicing holds, a later Finished clears it")
    func lastCheckInIsTheLatest() throws {
        let room = try makeRoom()
        try give([room.maya], room.first, on: "2026-10-01", confirm: true, in: room)
        try work(room.maya, on: room.first, .keepPracticing, closed: "2026-10-05", in: room)

        let held = try #require(try item(room.maya, in: room))
        #expect(held.tier == .almostReady)
        #expect(held.reasons == ["Last check-in: needs more practice"])
        #expect(held.previous.lastCheckIn == .keepPracticing)

        try work(room.maya, on: room.first, .done, closed: "2026-10-09", in: room)
        let cleared = try #require(try item(room.maya, in: room))
        #expect(cleared.tier == .ready)
        #expect(cleared.previous.lastCheckIn == .done)
    }

    @Test("A shaky recall check holds her, unless the lesson was given again since; inferred checks don't count")
    func shakyRecallFromTheStore() throws {
        let room = try makeRoom()
        try give([room.maya, room.eli], room.first, on: "2026-10-01", confirm: true, in: room)
        try recall(room.maya, on: room.first, .shaky, on: "2026-10-10", in: room)
        // Eli's shaky check came before she was given it again on 10-01.
        try recall(room.eli, on: room.first, .shaky, on: "2026-09-20", in: room)

        let maya = try #require(try item(room.maya, in: room))
        #expect(maya.tier == .almostReady)
        #expect(maya.reasons == ["Recall check was shaky"])
        #expect(try #require(try item(room.eli, in: room)).tier == .ready)

        // A later retained check, inferred from a later lesson, says nothing the guide saw.
        try recall(room.maya, on: room.first, .retained, on: "2026-10-12", source: .covered, in: room)
        #expect(try #require(try item(room.maya, in: room)).tier == .almostReady)
        // One she ran herself does.
        try recall(room.maya, on: room.first, .retained, on: "2026-10-13", in: room)
        #expect(try #require(try item(room.maya, in: room)).tier == .ready)
    }

    @Test("Confirmation is not mastery: a confirmed child is Ready and still reads as not mastered")
    func confirmationIsNotMastery() throws {
        let room = try makeRoom()
        try give([room.maya], room.first, on: "2026-10-01", confirm: true, in: room)
        try give([room.eli], room.first, on: "2026-10-01", confirm: false, in: room)

        let maya = try #require(try item(room.maya, in: room))
        #expect(maya.tier == .ready)
        #expect(maya.basis == .confirmed)
        #expect(!maya.previous.mastered)
        #expect(maya.previous.summary.hasSuffix("Not mastered yet"))
        // Not confirmed: not in the queue at all.
        #expect(try item(room.eli, in: room) == nil)

        // Reading the queue writes nothing, and never a mastery mark.
        #expect(!room.context.hasChanges)
        #expect(room.context.safeFetch(CDFetchRequest(CDLessonPresentation.self)).allSatisfy { $0.masteredAt == nil })
    }

    @Test("A classmate's open copy of linked work isn't hers")
    func classmatesCopyIsNotHers() throws {
        let room = try makeRoom()
        let given = try give([room.maya, room.eli], room.first, on: "2026-10-01", confirm: true, in: room)
        let repository = WorkRepository(context: room.context)
        let copies = try [room.maya, room.eli].map { student in
            try repository.createWork(
                studentID: try #require(student.id), lessonID: try #require(room.first.id),
                kind: .practiceLesson, presentationID: given.id, saveImmediately: false
            )
        }
        for copy in copies {
            for other in copies where other !== copy {
                let participant = CDWorkParticipantEntity(context: room.context)
                participant.id = UUID()
                participant.studentID = other.studentID
                participant.work = copy
            }
        }
        copies[0].status = .done

        #expect(try #require(try item(room.maya, in: room)).tier == .ready)
        let eli = try #require(try item(room.eli, in: room))
        #expect(eli.tier == .almostReady)
        #expect(eli.reasons == ["1 piece of work still open"])
    }
}
