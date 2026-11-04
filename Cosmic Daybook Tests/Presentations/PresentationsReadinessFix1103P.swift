import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-11-03, what Presentations calls ready: a mastery mark didn't
/// count as confirmation (#5, the blocking engine's side), Ready and Brewing
/// didn't redraw for a rule, order, sub-area or participant change (#6), the
/// holding-up marker often marked nobody (#9), and a departed or hidden child
/// kept a plan brewing and counted in "N of M ready" (#12).
@Suite("Presentations readiness (bug hunt 2026-11-03)")
@MainActor
struct PresentationsReadinessFix1103PTests {

    // MARK: - #5 A mastery mark counts as confirmation

    @Test("A mastery mark on the earlier lesson counts as confirmation in Presentations")
    func masteryMarkCountsAsConfirmation() async throws {
        let room = try Fix1103PRoom()
        let context = room.context
        let presentation = try room.given([room.ada])
        // The Checklist's Mastered: a history row with a mark, no confirmation.
        try room.historyRow(room.ada, lesson: room.first, on: nil, mastered: true)
        let next = try room.plan([room.ada])
        #expect(CoreDataTestHelpers.save(context))

        let results = BlockingAlgorithmEngine.checkBlocking(
            forBatch: [next], lessons: [room.first, room.second],
            allLessonAssignments: [presentation, next], workModels: []
        )
        let nextID = try #require(next.id)
        let adaID = try room.id(room.ada)
        let readiness = try #require(results[nextID]?.perStudentReadiness[adaID])
        #expect(readiness.teacherConfirmed)
        #expect(readiness.isReady)

        let vm = PresentationsViewModel()
        await room.update(vm)
        #expect(vm.readyLessons.contains(next))
        #expect(!vm.blockedLessons.contains(next))
    }

    @Test("A mastery mark with no presentation of the earlier lesson is enough")
    func masteryMarkWithoutPresentation() throws {
        let room = try Fix1103PRoom()
        let context = room.context
        try room.historyRow(room.ada, lesson: room.first, on: nil, mastered: true)
        let next = try room.plan([room.ada])
        #expect(CoreDataTestHelpers.save(context))

        let results = BlockingAlgorithmEngine.checkBlocking(
            forBatch: [next], lessons: [room.first, room.second], allLessonAssignments: [next], workModels: []
        )
        #expect(results[try #require(next.id)]?.isBlocked == false)
    }

    // MARK: - #6 Redrawing for what the engine reads

    @Test("Turning off the earlier lesson's rules redraws Brewing")
    func ruleOverrideRedraws() async throws {
        let room = try Fix1103PRoom()
        _ = try room.given([room.ada])
        let next = try room.plan([room.ada])
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = PresentationsViewModel()
        await room.update(vm)
        #expect(vm.blockedLessons.contains(next))

        room.first.confirmationOverride = .no
        #expect(CoreDataTestHelpers.save(room.context))
        await room.update(vm)
        #expect(vm.readyLessons.contains(next))
    }

    @Test("A sub-area's default rules redraw Brewing")
    func sequenceSettingsRedraw() async throws {
        let room = try Fix1103PRoom()
        _ = try room.given([room.ada])
        let next = try room.plan([room.ada])
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = PresentationsViewModel()
        await room.update(vm)
        #expect(vm.blockedLessons.contains(next))

        let settings = CDLessonSequenceSettings(context: room.context)
        settings.area = "Math"
        settings.sequence = "Counting"
        settings.requiresPractice = false
        settings.requiresTeacherConfirmation = false
        #expect(CoreDataTestHelpers.save(room.context))
        await room.update(vm)
        #expect(vm.readyLessons.contains(next))
    }

    @Test("Reordering the sequence redraws Brewing")
    func reorderRedraws() async throws {
        let room = try Fix1103PRoom()
        _ = try room.given([room.ada])
        let next = try room.plan([room.ada])
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = PresentationsViewModel()
        await room.update(vm)
        #expect(vm.blockedLessons.contains(next))

        // The second lesson moves ahead of the first: nothing comes before it now.
        room.second.orderInSequence = 0
        #expect(CoreDataTestHelpers.save(room.context))
        await room.update(vm)
        #expect(vm.readyLessons.contains(next))
    }

    @Test("A child finishing her part of shared work redraws Brewing")
    func participantCompletionRedraws() async throws {
        let room = try Fix1103PRoom()
        let presentation = try room.given([room.ada], confirmed: [room.ada])
        let work = CoreDataTestHelpers.seedWorkModel(
            in: room.context, studentID: try room.id(room.ada), lessonID: try #require(room.first.id)
        )
        work.presentationID = presentation.id?.uuidString
        let participant = CDWorkParticipantEntity(context: room.context)
        participant.studentID = try room.id(room.ada).uuidString
        participant.work = work
        let next = try room.plan([room.ada])
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = PresentationsViewModel()
        await room.update(vm)
        #expect(vm.blockedLessons.contains(next))

        participant.completedAt = Date()
        #expect(CoreDataTestHelpers.save(room.context))
        await room.update(vm)
        #expect(vm.readyLessons.contains(next))
    }

    @Test("The screen reloads for rule, participant and mastery-mark changes")
    func watchedEntities() {
        #expect(PresentationsView.watchedEntityNames.isSuperset(of: [
            "Lesson", "LessonSequenceSettings", "WorkParticipantEntity", "LessonPresentation"
        ]))
    }

    // MARK: - #9 Who holds a brewing lesson up

    @Test("The holding-up marker names the child the engine finds not ready, in a group from two earlier groups")
    func markerFollowsTheEngine() async throws {
        let room = try Fix1103PRoom()
        _ = try room.given([room.ada, room.maya], confirmed: [room.ada, room.maya])
        _ = try room.given([room.ben])
        let next = try room.plan([room.ada, room.ben])
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = PresentationsViewModel()
        await room.update(vm)
        #expect(vm.blockedLessons.contains(next))
        #expect(vm.blockingStudentIDs(of: next) == [try room.id(room.ben)])
    }

    // MARK: - #12 Children who aren't shown

    @Test("A departed child doesn't keep a plan in Brewing")
    func departedChildDoesNotHoldAPlan() async throws {
        let room = try Fix1103PRoom()
        _ = try room.given([room.ada], confirmed: [room.ada])
        let next = try room.plan([room.ada, room.ben])
        room.ben.enrollmentStatus = .withdrawn
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = PresentationsViewModel()
        await room.update(vm)
        #expect(vm.readyLessons.contains(next))
        #expect(!vm.blockedLessons.contains(next))
    }

    @Test("A hidden test child neither holds a plan up nor counts in N of M ready")
    func hiddenTestChildIsNotJudged() async throws {
        let room = try Fix1103PRoom()
        let tester = CoreDataTestHelpers.seedStudent(in: room.context, firstName: "Test", lastName: "Kid")
        _ = try room.given([room.ada], confirmed: [room.ada])
        let next = try room.plan([room.ada, room.maya, tester])
        #expect(CoreDataTestHelpers.save(room.context))

        let vm = PresentationsViewModel()
        await room.update(vm, showTestStudents: false, testNames: "Test Kid")
        #expect(vm.blockedLessons.contains(next))
        let nextID = try #require(next.id)
        let result = try #require(vm.blockingResults[nextID])
        #expect(Set(result.perStudentReadiness.keys) == [try room.id(room.ada), try room.id(room.maya)])
        #expect(result.readyStudentIDs == [try room.id(room.ada)])

        let alone = try room.plan([room.ada, tester])
        #expect(CoreDataTestHelpers.save(room.context))
        await room.update(vm, showTestStudents: false, testNames: "Test Kid")
        #expect(vm.readyLessons.contains(alone))
    }
}
