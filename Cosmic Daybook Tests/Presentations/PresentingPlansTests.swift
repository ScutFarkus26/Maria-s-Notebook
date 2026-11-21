import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Domain logic fixes, Phase 4 (review 2026-11-20): the pieces with new entry
// points — the Checklist's Not Mastered (R2), Siri and the one plan resolver
// (R12), and setting one child's fact on a group presentation (R24).

@Suite("Presenting plans (domain logic Phase 4)")
@MainActor
struct PresentingPlansTests {

    // MARK: - R2: Not Mastered on the Checklist

    @Test("Not Mastered on the Checklist takes back only the mastery mark")
    func checklistNotMasteredChangesOnlyMasteryRows() throws {
        let room = try PresentingRoom.make()
        _ = try room.givenTwiceWithOpenWork()
        let cell = CellIdentifier(studentID: room.adaID, lessonID: room.first.id!)
        let checklist = room.checklist()
        checklist.perform(.markComplete, on: cell, context: room.context)
        let given = room.assignments(room.first).filter(\.isPresented).count

        checklist.perform(.unmarkMastered, on: cell, context: room.context)

        let rows = room.rows(room.ada, room.first)
        #expect(rows.count == 2, "her history rows stay")
        #expect(rows.allSatisfy { $0.state == .presented && $0.masteredAt == nil })
        #expect(room.assignments(room.first).filter(\.isPresented).count == given, "her presentations stay")
        #expect(room.works(room.ada, room.first).map(\.status) == [.mastered], "closed work keeps its verdict")
        #expect(!room.context.hasChanges)
    }

    @Test("A mastered cell's Mastered step reads Not Mastered; the other rungs reached do nothing")
    func ladderStepOnMasteredCell() {
        #expect(ChecklistLadderStep.mastered.action(at: .mastered) == .unmarkMastered)
        #expect(ChecklistLadderStep.mastered.action(at: .presented) == .markComplete)
        #expect(ChecklistLadderStep.presented.action(at: .mastered) == nil)
        #expect(ChecklistLadderStep.practicing.action(at: .presented) == .markPracticing)
    }

    // MARK: - R12: Siri and the one resolver

    @Test("A second Siri \"presented\" the same day makes no second record")
    func secondSiriPresentedIsAnEdit() throws {
        let room = try PresentingRoom.make()
        let now = Date()
        let first = try MarkLessonPresentedIntent.record(room.first, for: room.ada, on: now, in: room.context)
        try room.context.save()
        let second = try MarkLessonPresentedIntent.record(room.first, for: room.ada, on: now, in: room.context)
        try room.context.save()

        #expect(first == .newRecord)
        #expect(second == .alreadyRecorded)
        #expect(room.assignments(room.first).filter(\.isPresented).count == 1)
        #expect(room.rows(room.ada, room.first).count == 1)
    }

    @Test("Siri on a child already given the lesson with her group that day records nothing more")
    func siriAfterGroupPresentation() throws {
        let room = try PresentingRoom.make()
        let today = try room.day("2026-11-20").addingTimeInterval(9 * 3600)
        let group = PresentationFactory.makeDraft(
            lesson: room.first, students: [room.ada, room.ben], context: room.context
        )
        _ = try LifecycleService.recordPresentation(from: group, presentedAt: today, modelContext: room.context)
        try room.context.save()
        let givenAt = group.presentedAt

        let origin = try MarkLessonPresentedIntent.record(
            room.first, for: room.ada, on: today.addingTimeInterval(3600), in: room.context
        )

        #expect(origin == .alreadyRecorded)
        #expect(room.assignments(room.first).filter(\.isPresented).count == 1)
        #expect(group.presentedAt == givenAt, "the group's presentation keeps its time")
    }

    @Test("Giving some of a group plan splits them off; the others keep the plan and its day")
    func subsetOfAGroupPlanSplits() throws {
        let room = try PresentingRoom.make()
        let thursday = try room.day("2026-11-19")
        let plan = PresentationFactory.makeDraft(
            lesson: room.first, students: [room.ada, room.ben], context: room.context
        )
        plan.schedule(for: thursday)
        try room.context.save()

        let resolved = PresentationRecorder.resolvePlan(
            lesson: room.first, present: [room.ada], on: try room.day("2026-11-18"), context: room.context
        )

        #expect(resolved.origin == .plannedLesson)
        #expect(resolved.assignment != plan)
        #expect(resolved.assignment.resolvedStudentIDs == [room.adaID])
        #expect(plan.resolvedStudentIDs == [room.benID], "Ben keeps the plan")
        #expect(plan.scheduledFor == thursday, "and its day")
    }

    // MARK: - R24: one child's fact

    @Test("Setting one child's needs-practice leaves her classmate's as it was")
    func setOneChildsFact() throws {
        let room = try PresentingRoom.make()
        let given = try room.given(room.first, to: [room.ada, room.ben], on: "2026-10-05")

        given.set(.needsPractice, to: true, for: [room.adaID])

        #expect(given.value(.needsPractice, for: room.adaID))
        #expect(!given.value(.needsPractice, for: room.benID))
        #expect(given.needsPractice, "the group's record says some child needs it, for older builds")

        given.set(.needsPractice, to: false, for: [room.adaID])
        #expect(!given.needsPractice, "no child needs it now")

        given.set(.needsPractice, to: true)
        #expect(given.value(.needsPractice, for: room.benID), "nil sets everyone")
        #expect(room.rows(room.ben, room.first).first?.needsPractice == nil, "her own value is cleared")
    }
}
