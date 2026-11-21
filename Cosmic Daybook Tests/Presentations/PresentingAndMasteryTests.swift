import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Domain logic fixes, Phase 4, R2 (review 2026-11-20): one mastery rule. Each
// test goes through the path a guide (or Claude) uses, so it reads the same on
// main, where it fails, and after the fix.

@Suite("Mastery paths agree (domain logic Phase 4)")
@MainActor
struct PresentingAndMasteryTests {

    enum MasteryPath: String, CaseIterable, CustomTestStringConvertible {
        case checklistCell, checklistSelection, claude, presentationSheet
        var testDescription: String { rawValue }
    }

    private func markMastered(_ room: PresentingRoom, by path: MasteryPath, latest: CDLessonAssignment) async throws {
        let cell = CellIdentifier(studentID: room.adaID, lessonID: room.first.id!)
        switch path {
        case .checklistCell:
            room.checklist().perform(.markComplete, on: cell, context: room.context)
        case .checklistSelection:
            let viewModel = room.checklist()
            viewModel.selectedCells = [cell]
            viewModel.batchMarkProficient(context: room.context)
        case .claude:
            _ = try await room.tool("mark_mastered").handler([
                "lesson": .string(room.first.name),
                "student_names": .array([.string("Ada")])
            ])
        case .presentationSheet:
            let viewModel = PresentationDetailViewModel(
                lessonAssignment: latest, viewContext: room.context, saveCoordinator: room.coordinator
            )
            viewModel.updateProficiencyState(
                lessonID: latest.lessonID, studentIDs: latest.studentIDs,
                state: .proficient, guideChangedState: true
            )
            #expect(room.coordinator.save(room.context, reason: "test"))
        }
    }

    @Test("Every mastery path marks every row she has and closes her open work as Mastered",
          arguments: MasteryPath.allCases)
    func everyMasteryPathAgrees(_ path: MasteryPath) async throws {
        let room = try PresentingRoom.make()
        let latest = try room.givenTwiceWithOpenWork()

        try await markMastered(room, by: path, latest: latest)

        let rows = room.rows(room.ada, room.first)
        #expect(rows.count == 2, "no row is added")
        #expect(rows.allSatisfy { $0.state == .proficient && $0.masteredAt != nil }, "every row she has is marked")
        let works = room.works(room.ada, room.first)
        #expect(works.count == 1, "no work is made")
        #expect(works.map(\.status) == [.mastered], "her open work closes as Mastered")
        #expect(!room.context.hasChanges)
    }

    @Test("Mastered on the Checklist and from Claude make no work for a child who has none",
          arguments: [MasteryPath.checklistCell, .claude])
    func masteryMakesNoWork(_ path: MasteryPath) async throws {
        let room = try PresentingRoom.make()
        let assignment = try room.given(room.first, to: [room.ada], on: "2026-10-05")
        try room.context.save()

        try await markMastered(room, by: path, latest: assignment)

        #expect(room.works(room.ada, room.first).isEmpty)
        #expect(room.rows(room.ada, room.first).allSatisfy(SequenceStanding.isMasteryMark))
    }

    @Test("A row carrying only masteredAt counts as already mastered for Claude")
    func masteredAtAloneIsAlreadyMastered() async throws {
        let room = try PresentingRoom.make()
        try room.given(room.first, to: [room.ada], on: "2026-10-05")
        let row = try #require(room.rows(room.ada, room.first).first)
        row.masteredAt = try room.day("2026-10-07")
        try room.context.save()

        let output = try await room.tool("mark_mastered").handler([
            "lesson": .string(room.first.name),
            "student_names": .array([.string("Ada")])
        ])

        #expect(output.contains("Already mastered"))
        #expect(row.masteredAt == (try room.day("2026-10-07")), "the recorded day is kept")
    }

    @Test("The same-id lesson merge raises the state along with the mastered day")
    func lessonMergeRaisesState() throws {
        let room = try PresentingRoom.make()
        try room.given(room.first, to: [room.ada], on: "2026-10-05")
        let row = try #require(room.rows(room.ada, room.first).first)
        let duplicate = CDLessonPresentation(context: room.context)
        duplicate.studentID = row.studentID
        duplicate.lessonID = row.lessonID
        duplicate.state = .proficient
        duplicate.masteredAt = try room.day("2026-10-09")

        DataCleanupService.mergeLessonPresentation(canonical: row, duplicate: duplicate)

        #expect(row.state == .proficient)
        #expect(row.masteredAt == (try room.day("2026-10-09")))
    }

    @Test("Claude can take a mastery mark back")
    func claudeUnmarks() async throws {
        let room = try PresentingRoom.make()
        try room.givenTwiceWithOpenWork()
        let tool = try room.tool("mark_mastered")
        _ = try await tool.handler(["lesson": .string(room.first.name), "student_names": .array([.string("Ada")])])

        let output = try await tool.handler([
            "lesson": .string(room.first.name), "student_names": .array([.string("Ada")]), "unmark": .bool(true)
        ])

        #expect(room.rows(room.ada, room.first).allSatisfy { !SequenceStanding.isMasteryMark($0) })
        #expect(output.contains("No longer mastered"))
    }
}
