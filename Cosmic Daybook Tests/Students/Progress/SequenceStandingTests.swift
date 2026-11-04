import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A child's standing on a sequence is read from her presentation rows and
/// the sequence's lessons, never stored (2026-11-03, replacing track
/// enrollments and steps).
@Suite("Sequence standing")
@MainActor
struct SequenceStandingTests {

    private struct Room {
        let context: NSManagedObjectContext
        let owner: AnyObject
        let maya: CDStudent
        let mayaID: String
        let chains: [CDLesson]
        let grammar: [CDLesson]
    }

    /// Maya, a three-lesson Math — Chains sequence and a two-lesson Language
    /// — Grammar sequence, plus a classmate with her own rows on Grammar.
    private func makeRoom() throws -> Room {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "S")
        let chains = (0..<3).map { index -> CDLesson in
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Chain \(index)", area: "Math", sequence: "Chains"
            )
            lesson.orderInSequence = Int64(index)
            return lesson
        }
        let grammar = (0..<2).map { index -> CDLesson in
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Grammar \(index)", area: "Language", sequence: "Grammar"
            )
            lesson.orderInSequence = Int64(index)
            return lesson
        }
        let other = CoreDataTestHelpers.seedStudent(in: context, firstName: "Other", lastName: "O")
        let otherRow = CDLessonPresentation(context: context)
        otherRow.studentID = try #require(other.id).uuidString
        otherRow.lessonID = try #require(grammar[0].id).uuidString
        otherRow.state = .proficient
        try context.save()
        return Room(
            context: context, owner: stack, maya: maya, mayaID: try #require(maya.id).uuidString,
            chains: chains, grammar: grammar
        )
    }

    @discardableResult
    private func give(
        _ lesson: CDLesson, to studentID: String, on day: Date, mastered: Bool = false,
        in context: NSManagedObjectContext
    ) throws -> CDLessonPresentation {
        let row = CDLessonPresentation(context: context)
        row.studentID = studentID
        row.lessonID = try #require(lesson.id).uuidString
        row.presentedAt = day
        row.state = mastered ? .proficient : .presented
        row.masteredAt = mastered ? day : nil
        return row
    }

    @Test("A child with no presentation rows has no standings")
    func noRowsNoStandings() throws {
        let room = try makeRoom()
        #expect(SequenceStandingLoader.standings(forStudentID: room.mayaID, in: room.context).isEmpty)
    }

    @Test("One lesson given puts her in progress on that sequence, up to the next lesson")
    func inProgressAfterOneLesson() throws {
        let room = try makeRoom()
        let monday = try CoreDataTestHelpers.day("2026-10-05")
        try give(room.chains[0], to: room.mayaID, on: monday, in: room.context)
        try room.context.save()

        let standings = SequenceStandingLoader.standings(forStudentID: room.mayaID, in: room.context)
        #expect(standings.map(\.id) == ["math|chains"])
        let chains = try #require(standings.first)
        #expect(chains.title == "Math — Chains")
        #expect(chains.total == 3)
        #expect(chains.givenCount == 1)
        #expect(chains.masteredCount == 0)
        #expect(chains.isInProgress)
        #expect(!chains.isFinished)
        #expect(chains.nextLesson?.objectID == room.chains[1].objectID)
        #expect(chains.firstGivenAt == monday)
        #expect(chains.lastActivityAt == monday)
    }

    @Test("Mastery comes from the mark, and the next lesson is the first not yet given")
    func masteryAndNext() throws {
        let room = try makeRoom()
        let first = try CoreDataTestHelpers.day("2026-09-01")
        let later = try CoreDataTestHelpers.day("2026-10-01")
        try give(room.chains[0], to: room.mayaID, on: first, mastered: true, in: room.context)
        // Given out of order: the second lesson skipped, the third given.
        try give(room.chains[2], to: room.mayaID, on: later, in: room.context)
        try room.context.save()

        let chains = SequenceStandingLoader.standing(
            forStudentID: room.mayaID, area: "Math", sequence: "Chains", in: room.context
        )
        #expect(chains.masteredCount == 1)
        #expect(chains.givenCount == 2)
        #expect(chains.nextLesson?.objectID == room.chains[1].objectID)
        #expect(chains.firstGivenAt == first)
        #expect(chains.lastActivityAt == later)
        #expect(chains.progressPercent == 1.0 / 3.0)
    }

    @Test("Every lesson mastered is finished, and no longer in progress")
    func finished() throws {
        let room = try makeRoom()
        let day = try CoreDataTestHelpers.day("2026-10-05")
        for lesson in room.grammar {
            try give(lesson, to: room.mayaID, on: day, mastered: true, in: room.context)
        }
        try room.context.save()

        let standings = SequenceStandingLoader.standings(forStudentID: room.mayaID, in: room.context)
        let grammar = try #require(standings.first { $0.sequence == "Grammar" })
        #expect(grammar.isFinished)
        #expect(!grammar.isInProgress)
        #expect(grammar.nextLesson == nil)
        #expect(standings.filter(\.isInProgress).isEmpty)
    }

    @Test("Standings come in curriculum order, one per sequence, and a classmate's rows never count")
    func orderAndScope() throws {
        let room = try makeRoom()
        let day = try CoreDataTestHelpers.day("2026-10-05")
        try give(room.chains[0], to: room.mayaID, on: day, in: room.context)
        try give(room.chains[1], to: room.mayaID, on: day, in: room.context)
        try give(room.grammar[1], to: room.mayaID, on: day, in: room.context)
        try room.context.save()

        let standings = SequenceStandingLoader.standings(forStudentID: room.mayaID, in: room.context)
        #expect(standings.map(\.title) == ["Language — Grammar", "Math — Chains"])
        let grammar = try #require(standings.first)
        // The classmate mastered Grammar 0; Maya has not been given it.
        #expect(grammar.givenCount == 1)
        #expect(grammar.masteredCount == 0)
        #expect(grammar.nextLesson?.objectID == room.grammar[0].objectID)
    }

    @Test("A sequence with padded or differently cased names still resolves")
    func foldsNames() throws {
        let room = try makeRoom()
        let day = try CoreDataTestHelpers.day("2026-10-05")
        try give(room.chains[0], to: room.mayaID, on: day, in: room.context)
        try room.context.save()

        let chains = SequenceStandingLoader.standing(
            forStudentID: room.mayaID, area: " math ", sequence: "CHAINS", in: room.context
        )
        #expect(chains.total == 3)
        #expect(chains.givenCount == 1)
        #expect(chains.id == "math|chains")
    }
}
