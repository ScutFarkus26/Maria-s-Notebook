import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, P2 #65–68: a child who finished her practice stayed
/// "Waiting for work", a confirmation on the other giving of a lesson was
/// ignored, the backlog didn't refresh after a confirmation, a withdrawal or
/// the test-students setting, and duplicate rows could trap.
@Suite("Presentations backlog (bug hunt 2026-10-10)")
@MainActor
struct PresentationsBacklogFix1010ITests {

    private struct Room {
        let stack: CoreDataStack
        let ada: CDStudent
        let first: CDLesson
        let second: CDLesson
        var context: NSManagedObjectContext { stack.viewContext }
    }

    /// Ada, and a two-lesson sequence; the second needs the first's practice
    /// and a confirmation (the built-in rules).
    private func makeRoom() throws -> Room {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane")
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "First", area: "Math", sequence: "Counting")
        first.orderInSequence = 1
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Second", area: "Math", sequence: "Counting")
        second.orderInSequence = 2
        #expect(CoreDataTestHelpers.save(context))
        return Room(stack: stack, ada: ada, first: first, second: second)
    }

    private func given(
        _ room: Room, on day: String, needsPractice: Bool = false, confirmed: Bool = false
    ) throws -> CDLessonAssignment {
        let adaID = try #require(room.ada.id)
        let assignment = PresentationFactory.makeDraft(
            lessonID: try #require(room.first.id), studentIDs: [adaID], context: room.context
        )
        assignment.needsPractice = needsPractice
        assignment.markPresented(at: try CoreDataTestHelpers.day(day))
        if confirmed { assignment.confirmStudent(adaID) }
        return assignment
    }

    private func nextPlan(_ room: Room) throws -> CDLessonAssignment {
        PresentationFactory.makeDraft(
            lessonID: try #require(room.second.id), studentIDs: [try #require(room.ada.id)], context: room.context
        )
    }

    private func update(
        _ vm: PresentationsViewModel, _ room: Room, showTestStudents: Bool = true, testNames: String = ""
    ) async {
        vm.update(
            viewContext: room.context,
            calendar: AppCalendar.shared,
            inboxOrderRaw: "",
            missWindow: .all,
            showTestStudents: showTestStudents,
            testStudentNamesRaw: testNames,
            lessons: room.context.safeFetch(CDFetchRequest(CDLesson.self)),
            students: room.context.safeFetch(CDFetchRequest(CDStudent.self))
        )
        await vm.pendingUpdateTask?.value
    }

    // MARK: - #65 Closed practice

    @Test("A child whose practice is closed is ready, not waiting for work")
    func closedPracticeIsReady() async throws {
        let room = try makeRoom()
        let presentation = try given(room, on: "2026-09-14", needsPractice: true, confirmed: true)
        let work = CoreDataTestHelpers.seedWorkModel(
            in: room.context, studentID: try #require(room.ada.id), lessonID: try #require(room.first.id)
        )
        work.presentationID = presentation.id?.uuidString
        work.status = .done
        let plan = try nextPlan(room)
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = PresentationsViewModel()
        await update(vm, room)

        #expect(vm.readyLessons.contains(plan))
        #expect(!vm.blockedLessons.contains(plan))
    }

    // MARK: - #66 The other giving's confirmation

    @Test("A confirmation on either giving of the preceding lesson counts")
    func confirmationOnEitherGivingCounts() throws {
        let room = try makeRoom()
        let unconfirmed = try given(room, on: "2026-09-01")
        let confirmed = try given(room, on: "2026-09-14", confirmed: true)
        let plan = try nextPlan(room)
        let lessons = [room.first, room.second]
        let planID = try #require(plan.id)
        let adaID = try #require(room.ada.id)

        for order in [[unconfirmed, confirmed, plan], [confirmed, unconfirmed, plan]] {
            let results = BlockingAlgorithmEngine.checkBlocking(
                forBatch: [plan], lessons: lessons, allLessonAssignments: order, workModels: []
            )
            let readiness = try #require(results[planID]?.perStudentReadiness[adaID])
            #expect(readiness.teacherConfirmed)
            #expect(readiness.isReady)
        }
    }

    // MARK: - #68 Duplicate rows

    @Test("Two lesson rows with one id don't trap the blocking check or the days-since count")
    func duplicateLessonRowsDoNotTrap() async throws {
        let room = try makeRoom()
        let copy = CoreDataTestHelpers.seedLesson(in: room.context, name: "First", area: "Math", sequence: "Counting")
        copy.id = room.first.id
        copy.orderInSequence = 1
        _ = try given(room, on: "2026-09-14", confirmed: true)
        let plan = try nextPlan(room)
        #expect(CoreDataTestHelpers.save(room.context))

        let lessons = room.context.safeFetch(CDFetchRequest(CDLesson.self))
        #expect(lessons.count == 3)
        let results = BlockingAlgorithmEngine.checkBlocking(
            forBatch: [plan], lessons: lessons, allLessonAssignments: [], workModels: []
        )
        #expect(results[try #require(plan.id)] != nil)

        let vm = PresentationsViewModel()
        await update(vm, room)
        #expect(vm.daysSinceLastLessonByStudent[try #require(room.ada.id)] != nil)
    }

    // MARK: - #67 Refreshing

    @Test("Confirming a child refreshes the backlog")
    func confirmationRefreshes() async throws {
        let room = try makeRoom()
        let presentation = try given(room, on: "2026-09-14")
        let plan = try nextPlan(room)
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = PresentationsViewModel()
        await update(vm, room)
        #expect(vm.blockedLessons.contains(plan))

        presentation.confirmStudent(try #require(room.ada.id))
        #expect(CoreDataTestHelpers.save(room.context))
        room.context.processPendingChanges()
        await update(vm, room)
        #expect(vm.readyLessons.contains(plan))
    }

    @Test("A withdrawal and the test-students setting refresh the roster the backlog uses")
    func withdrawalAndTestStudentsRefresh() async throws {
        let room = try makeRoom()
        let tester = CoreDataTestHelpers.seedStudent(in: room.context, firstName: "Test", lastName: "Kid")
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = PresentationsViewModel()
        await update(vm, room, showTestStudents: true, testNames: "Test Kid")
        #expect(Set(vm.cachedStudents) == [room.ada, tester])

        await update(vm, room, showTestStudents: false, testNames: "Test Kid")
        #expect(vm.cachedStudents == [room.ada])

        room.ada.enrollmentStatus = .withdrawn
        #expect(CoreDataTestHelpers.save(room.context))
        await update(vm, room, showTestStudents: false, testNames: "Test Kid")
        #expect(vm.cachedStudents.isEmpty)
    }
}
