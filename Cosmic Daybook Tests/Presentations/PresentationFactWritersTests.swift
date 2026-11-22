import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Domain logic Phase 10, cold review finding 3: the per-child presentation
// facts (R24, Decision 15) had a reader but no writer, so every writer still
// set the group record's field directly. Once a child's row carries her own
// value, a direct "yes" on the group is lost for her: her own "no" wins. The
// writers now go through `set(_:to:for:)`, so the group's value and the
// children's can't disagree.

@Suite("Presentation fact writers (domain logic, Phase 10)")
@MainActor
struct PresentationFactWritersTests {

    private typealias Fact = CDLessonAssignment.ChildFact

    /// Ada and Ben given the first lesson, each child's row carrying her own
    /// "no" for `fact`, as a writer for one child leaves them.
    private func givenWithOwnNos(_ fact: Fact, _ room: PresentingRoom) throws -> CDLessonAssignment {
        let given = try room.given(room.first, to: [room.ada, room.ben], on: "2026-10-05")
        given.set(fact, to: true, for: [room.benID])
        given.set(fact, to: false, for: [room.benID])
        try room.context.save()
        #expect(room.rows(room.ada, room.first).first?.ownValue(fact) == false)
        #expect(room.rows(room.ben, room.first).first?.ownValue(fact) == false)
        return given
    }

    /// Ada alone on a presentation whose row still carries her own "no" from
    /// when Ben was on it too.
    private func aloneWithAnOldNo(_ fact: Fact, _ room: PresentingRoom) throws -> CDLessonAssignment {
        let given = try givenWithOwnNos(fact, room)
        given.studentIDs = [room.adaID.uuidString]
        room.rows(room.ben, room.first).forEach(room.context.delete)
        try room.context.save()
        return given
    }

    private func saveSheet(_ given: CDLessonAssignment, needsAnother: Bool, _ room: PresentingRoom) throws {
        PresentationDetailActions().applyEditsToModel(
            lessonAssignment: given,
            editingLessonID: try #require(room.first.id),
            scheduledFor: nil,
            givenAt: try room.day("2026-10-05"),
            isPresented: true,
            notes: "",
            needsAnotherPresentation: needsAnother,
            selectedStudentIDs: [room.adaID, room.benID],
            studentsAll: [room.ada, room.ben],
            lessons: [room.first, room.second],
            calendar: AppCalendar.shared
        )
    }

    // MARK: - The whole presentation

    @Test("Turning Needs Another Presentation on in the sheet turns it on for every child")
    func sheetToggleReachesEveryChild() throws {
        let room = try PresentingRoom.make()
        let given = try givenWithOwnNos(.needsAnotherPresentation, room)

        try saveSheet(given, needsAnother: true, room)

        #expect(given.value(.needsAnotherPresentation, for: room.adaID))
        #expect(given.value(.needsAnotherPresentation, for: room.benID))
        #expect(given.needsAnotherPresentation, "older builds read the group's field")
    }

    @Test("A sheet Save that leaves the toggle alone keeps each child's own value")
    func untouchedToggleKeepsEachChilds() throws {
        let room = try PresentingRoom.make()
        let given = try room.given(room.first, to: [room.ada, room.ben], on: "2026-10-05")
        given.set(.needsAnotherPresentation, to: true, for: [room.benID])

        try saveSheet(given, needsAnother: given.needsAnotherPresentation, room)

        #expect(!given.value(.needsAnotherPresentation, for: room.adaID))
        #expect(given.value(.needsAnotherPresentation, for: room.benID))
    }

    // MARK: - One child on her own

    @Test("A meeting's Re-present on her own presentation leaves no old no on her row")
    func meetingRepresentClearsHerOldNo() throws {
        let room = try PresentingRoom.make()
        let given = try aloneWithAnOldNo(.needsAnotherPresentation, room)

        try MeetingLessonDecisions.flagForAnotherPresentation(given, studentID: room.adaID, context: room.context)

        #expect(room.rows(room.ada, room.first).first?.ownValue(.needsAnotherPresentation) == nil)
        given.studentIDs = [room.adaID, room.benID].map(\.uuidString)
        #expect(given.value(.needsAnotherPresentation, for: room.adaID), "Ben back on it doesn't undo hers")
    }
}
