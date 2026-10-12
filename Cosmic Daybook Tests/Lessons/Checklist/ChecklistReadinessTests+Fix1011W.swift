import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11, #17, #18 and #6: the checklist's "Not yet" is the
/// planner's readiness rule, its cells read each child's own copy of shared
/// work, and View Class Progress lands on the track's sequence.
@Suite("Checklist readiness (fix 10-11 W)")
@MainActor
struct ChecklistReadinessFix1011WTests {

    /// Math › Decimal: lesson A, then lesson B. No sequence settings, so B
    /// needs both practice on A and the guide's confirmation.
    private struct Fixture {
        let context: NSManagedObjectContext
        let maya: CDStudent
        let eli: CDStudent
        let lessonA: CDLesson
        let lessonB: CDLesson

        var mayaID: UUID { maya.id ?? UUID() }
        var eliID: UUID { eli.id ?? UUID() }

        /// A given presentation of A.
        @discardableResult
        func giveA(
            to students: [CDStudent], on day: String, confirming: [CDStudent] = []
        ) throws -> CDLessonAssignment {
            let given = CDLessonAssignment(context: context)
            given.lessonID = try #require(lessonA.id).uuidString
            given.studentIDs = students.map(\.cloudKitKey)
            given.markPresented(at: try CoreDataTestHelpers.day(day), snapshotLesson: false)
            for student in confirming {
                given.confirmStudent(try #require(student.id))
            }
            try context.save()
            return given
        }

        /// One Quick New Work on A, a linked copy per child, on `giving`.
        func copiesOfA(for students: [CDStudent], on giving: CDLessonAssignment) throws -> [CDWorkModel] {
            let repository = WorkRepository(context: context)
            let works = try students.map { student in
                try repository.createWork(
                    studentID: try #require(student.id), lessonID: try #require(lessonA.id),
                    kind: .practiceLesson, presentationID: giving.id, saveImmediately: false
                )
            }
            for work in works {
                for other in works where other !== work {
                    let participant = CDWorkParticipantEntity(context: context)
                    participant.id = UUID()
                    participant.studentID = other.studentID
                    participant.work = work
                }
            }
            try context.save()
            return works
        }

        /// The checklist's cell for a child and lesson.
        func cell(_ student: CDStudent, _ lesson: CDLesson) throws -> StudentChecklistRowState {
            let matrix = ChecklistMatrixBuilder.buildMatrix(
                students: [maya, eli], lessons: [lessonA, lessonB], context: context
            )
            let studentID = try #require(student.id)
            let lessonID = try #require(lesson.id)
            return try #require(matrix[studentID]?[lessonID])
        }

        /// What the planner says about the child for B: a plan of B for her,
        /// judged with every work row, open and closed.
        func engineReady(_ student: CDStudent) throws -> Bool {
            let plan = CDLessonAssignment(context: context)
            plan.lessonID = try #require(lessonB.id).uuidString
            plan.studentIDs = [student.cloudKitKey]
            defer { context.delete(plan) }
            let assignments = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
            let works = context.safeFetch(CDFetchRequest(CDWorkModel.self))
            let result = BlockingAlgorithmEngine.checkBlocking(
                forBatch: [plan], lessons: [lessonA, lessonB],
                allLessonAssignments: assignments, workModels: works
            )
            let planID = try #require(plan.id)
            let studentID = try #require(student.id)
            let readiness = try #require(result[planID]?.perStudentReadiness[studentID])
            return readiness.isReady
        }

        /// The checklist and the planner agree, and say `ready`.
        func expectAgreement(_ student: CDStudent, ready: Bool) throws {
            let checklistReady = try cell(student, lessonB).blockingReason == .none
            let plannerReady = try engineReady(student)
            #expect(checklistReady == plannerReady)
            #expect(checklistReady == ready)
        }
    }

    private func makeFixture() throws -> Fixture {
        // On disk, so an unsorted fetch comes back in the order rows were made.
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Park")
        let lessonA = CoreDataTestHelpers.seedLesson(in: context, name: "Decimal A", area: "Math", sequence: "Decimal")
        lessonA.orderInSequence = 0
        let lessonB = CoreDataTestHelpers.seedLesson(in: context, name: "Decimal B", area: "Math", sequence: "Decimal")
        lessonB.orderInSequence = 1
        try context.save()
        return Fixture(context: context, maya: maya, eli: eli, lessonA: lessonA, lessonB: lessonB)
    }

    // MARK: - One rule (#17)

    @Test("practice that exists only as closed work: both say ready")
    func closedPracticeIsReady() throws {
        let fixture = try makeFixture()
        let given = try fixture.giveA(to: [fixture.maya], on: "2026-09-08", confirming: [fixture.maya])
        let copies = try fixture.copiesOfA(for: [fixture.maya], on: given)
        copies[0].status = .mastered
        try fixture.context.save()

        try fixture.expectAgreement(fixture.maya, ready: true)
    }

    @Test("a confirmation recorded on her other giving counts")
    func confirmationOnTheOtherGivingCounts() throws {
        let fixture = try makeFixture()
        // The later giving is made first, so it comes back first; the earlier
        // one carries the confirmation.
        let later = try fixture.giveA(to: [fixture.maya], on: "2026-09-08")
        try fixture.giveA(to: [fixture.maya], on: "2026-09-01", confirming: [fixture.maya])
        let copies = try fixture.copiesOfA(for: [fixture.maya], on: later)
        copies[0].status = .mastered
        try fixture.context.save()

        try fixture.expectAgreement(fixture.maya, ready: true)
    }

    @Test("no work, on a giving that didn't ask for practice: ready, not 'needs practice'")
    func noWorkWithoutNeedsPracticeIsReady() throws {
        let fixture = try makeFixture()
        let given = try fixture.giveA(to: [fixture.maya], on: "2026-09-08", confirming: [fixture.maya])
        given.needsPractice = false
        try fixture.context.save()

        try fixture.expectAgreement(fixture.maya, ready: true)
    }

    @Test("a classmate's open copy doesn't hold Maya back")
    func classmatesCopyDoesNotBlock() throws {
        let fixture = try makeFixture()
        let given = try fixture.giveA(
            to: [fixture.maya, fixture.eli], on: "2026-09-08", confirming: [fixture.maya, fixture.eli]
        )
        let copies = try fixture.copiesOfA(for: [fixture.maya, fixture.eli], on: given)
        copies[0].status = .mastered
        try fixture.context.save()

        try fixture.expectAgreement(fixture.maya, ready: true)
        try fixture.expectAgreement(fixture.eli, ready: false)
        #expect(try fixture.cell(fixture.eli, fixture.lessonB).blockingReason == .practiceRequired)
    }

    // Guard: passes on the old code too.
    @Test("A not given to her: both say not ready, and the cell says why")
    func notPresentedIsNotReady() throws {
        let fixture = try makeFixture()
        try fixture.giveA(to: [fixture.maya], on: "2026-09-08", confirming: [fixture.maya])

        try fixture.expectAgreement(fixture.eli, ready: false)
        #expect(try fixture.cell(fixture.eli, fixture.lessonB).blockingReason == .prerequisiteNotPresented)
    }

    @Test("an unconfirmed giving with closed practice needs confirmation")
    func unconfirmedNeedsConfirmation() throws {
        let fixture = try makeFixture()
        let given = try fixture.giveA(to: [fixture.maya], on: "2026-09-08")
        let copies = try fixture.copiesOfA(for: [fixture.maya], on: given)
        copies[0].status = .mastered
        try fixture.context.save()

        try fixture.expectAgreement(fixture.maya, ready: false)
        #expect(try fixture.cell(fixture.maya, fixture.lessonB).blockingReason == .confirmationRequired)
    }

    @Test("a plan the guide unlocked is ready on the checklist, as in Presentations")
    func unlockedPlanIsReady() throws {
        let fixture = try makeFixture()
        let given = try fixture.giveA(to: [fixture.maya], on: "2026-09-08")
        _ = try fixture.copiesOfA(for: [fixture.maya], on: given)
        #expect(try fixture.cell(fixture.maya, fixture.lessonB).blockingReason != .none)

        // Review 2026-10-11 (a) #1: Ready to Present's unlock sets this on her plan of B.
        let plan = CDLessonAssignment(context: fixture.context)
        plan.lessonID = try #require(fixture.lessonB.id).uuidString
        plan.studentIDs = [fixture.maya.cloudKitKey]
        plan.manuallyUnblocked = true
        try fixture.context.save()

        #expect(try fixture.cell(fixture.maya, fixture.lessonB).blockingReason == .none)
    }

    // MARK: - Each child's own copy (#18)

    @Test("Maya's closed copy plus Eli's open one: Maya's cell is finished, Eli's is practicing")
    func cellReadsOwnCopy() throws {
        let fixture = try makeFixture()
        let given = try fixture.giveA(to: [fixture.maya, fixture.eli], on: "2026-09-08")
        let copies = try fixture.copiesOfA(for: [fixture.maya, fixture.eli], on: given)
        copies[0].status = .mastered
        try fixture.context.save()

        let mayas = try fixture.cell(fixture.maya, fixture.lessonA)
        #expect(mayas.isComplete)
        #expect(!mayas.isActive)
        #expect(mayas.contractID == copies[0].id)

        let elis = try fixture.cell(fixture.eli, fixture.lessonA)
        #expect(elis.isActive)
        #expect(elis.contractID == copies[1].id)
    }

    // Guard: passes on the old code too.
    @Test("a genuinely shared row shows on every child it carries")
    func sharedRowShowsForEveryone() throws {
        let fixture = try makeFixture()
        let row = CDWorkModel(context: fixture.context)
        row.lessonID = try #require(fixture.lessonA.id).uuidString
        row.studentID = fixture.maya.cloudKitKey
        row.status = .active
        row.createdAt = Date()
        for student in [fixture.maya, fixture.eli] {
            let participant = CDWorkParticipantEntity(context: fixture.context)
            participant.id = UUID()
            participant.studentID = student.cloudKitKey
            participant.work = row
        }
        try fixture.context.save()

        #expect(try fixture.cell(fixture.maya, fixture.lessonA).isActive)
        #expect(try fixture.cell(fixture.eli, fixture.lessonA).isActive)
    }

    // MARK: - View Class Progress (#6)

    @Test("View Class Progress opens the area and asks for the track's sequence")
    func viewClassProgressSelectsTheSequence() throws {
        let fixture = try makeFixture()
        let geometry = CoreDataTestHelpers.seedLesson(
            in: fixture.context, name: "Points and Lines", area: "Math", sequence: "Geometry"
        )
        geometry.orderInSequence = 0
        try fixture.context.save()
        let router = AppRouter.shared
        defer {
            router.checklistFilterArea = nil
            router.checklistFilterSequence = nil
        }
        // What `navigateToChecklist(area:sequence:)` leaves for the grid, without
        // moving the shared router's section.
        router.checklistFilterArea = "Math"
        router.checklistFilterSequence = "geometry "

        let viewModel = ClassAreaChecklistViewModel()
        viewModel.collapsedSequencesDefaults = UserDefaults(suiteName: "ChecklistFix1011W-\(UUID())") ?? .standard
        viewModel.loadData(context: fixture.context)

        #expect(viewModel.selectedArea == "Math")
        #expect(viewModel.pendingSequenceJump == "Geometry")
        #expect(router.checklistFilterArea == nil)
        #expect(router.checklistFilterSequence == nil)
    }
}
