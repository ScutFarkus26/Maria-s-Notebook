import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Split Off to a Different Group (2026-10-28): the children leave the plan
/// for one of their own, taking their entries and notes, and Undo puts every
/// piece back.
@Suite("Splitting children off a presentation")
@MainActor
struct PresentationSplitTests {

    private struct Room {
        let context: NSManagedObjectContext
        let ada: CDStudent
        let ben: CDStudent
        let cy: CDStudent
        let lesson: CDLesson
    }

    private func makeRoom() throws -> Room {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Ross")
        let cy = CoreDataTestHelpers.seedStudent(in: context, firstName: "Cy", lastName: "Moss")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Addition", sequence: "Fractions")
        #expect(CoreDataTestHelpers.save(context))
        return Room(context: context, ada: ada, ben: ben, cy: cy, lesson: lesson)
    }

    private func plans(_ context: NSManagedObjectContext) -> [CDLessonAssignment] {
        context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
    }

    private func split(
        _ moving: [CDStudent], off source: CDLessonAssignment, in room: Room
    ) throws -> PresentationSplit {
        let split = PresentationDetailActions().moveStudentsToInbox(
            from: source,
            currentLesson: room.lesson,
            studentsToMove: Set(try moving.map { try #require($0.id) }),
            studentsAll: [room.ada, room.ben, room.cy],
            lessonAssignmentsAll: plans(room.context),
            context: room.context
        )
        #expect(CoreDataTestHelpers.save(room.context))
        return try #require(split)
    }

    @Test("Splitting takes the child off the plan and onto a new one, with her entry and her own note")
    func splitMovesChildEntryAndNote() throws {
        let room = try makeRoom()
        let source = PresentationFactory.makeDraft(lesson: room.lesson, students: [room.ada, room.ben, room.cy], context: room.context)
        let adaID = try #require(room.ada.id)
        let entry = CDYearPlanEntry(context: room.context)
        entry.studentID = adaID.uuidString
        entry.lessonID = source.lessonID
        entry.status = .promoted
        entry.promotedAssignmentID = try #require(source.id).uuidString
        let adasNote = CoreDataTestHelpers.seedNote(in: room.context, body: "Ada needs the insets")
        adasNote.scope = .student(adaID)
        adasNote.lessonAssignment = source
        let groupNote = CoreDataTestHelpers.seedNote(in: room.context, body: "Whole group")
        groupNote.lessonAssignment = source
        #expect(CoreDataTestHelpers.save(room.context))

        let result = try split([room.ada], off: source, in: room)

        #expect(Set(source.resolvedStudentIDs) == Set(try [room.ben, room.cy].map { try #require($0.id) }))
        #expect(result.madeDestination)
        #expect(result.destination.resolvedStudentIDs == [adaID])
        #expect(result.destination.scheduledFor == nil)
        #expect(entry.promotedAssignmentID == result.destination.id?.uuidString)
        #expect(adasNote.lessonAssignment == result.destination)
        #expect(groupNote.lessonAssignment == source)
        #expect(result.canUndo)
    }

    @Test("Undo puts the child, her entry and her note back and deletes the plan the split made")
    func undoRestoresEverything() throws {
        let room = try makeRoom()
        let source = PresentationFactory.makeDraft(lesson: room.lesson, students: [room.ada, room.ben], context: room.context)
        let adaID = try #require(room.ada.id)
        let entry = CDYearPlanEntry(context: room.context)
        entry.studentID = adaID.uuidString
        entry.lessonID = source.lessonID
        entry.status = .promoted
        entry.promotedAssignmentID = try #require(source.id).uuidString
        let note = CoreDataTestHelpers.seedNote(in: room.context, body: "Ada")
        note.scope = .student(adaID)
        note.lessonAssignment = source
        #expect(CoreDataTestHelpers.save(room.context))

        let result = try split([room.ada], off: source, in: room)
        #expect(PresentationDetailActions().undoSplit(result, context: room.context))
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(Set(source.resolvedStudentIDs) == Set(try [room.ada, room.ben].map { try #require($0.id) }))
        #expect(entry.promotedAssignmentID == source.id?.uuidString)
        #expect(note.lessonAssignment == source)
        #expect(plans(room.context) == [source])
    }

    @Test("Undo keeps a draft the split reused, as it was before")
    func undoKeepsReusedDraft() throws {
        let room = try makeRoom()
        let source = PresentationFactory.makeDraft(lesson: room.lesson, students: [room.ada, room.ben], context: room.context)
        let waiting = PresentationFactory.makeDraft(lesson: room.lesson, students: [room.ada], context: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let result = try split([room.ada], off: source, in: room)
        #expect(result.destination == waiting)
        #expect(!result.madeDestination)

        #expect(PresentationDetailActions().undoSplit(result, context: room.context))
        #expect(CoreDataTestHelpers.save(room.context))
        #expect(Set(plans(room.context)) == [source, waiting])
        #expect(waiting.resolvedStudentIDs == [try #require(room.ada.id)])
        #expect(source.resolvedStudentIDs.count == 2)
    }

    @Test("Undo changes nothing once the new plan has been given")
    func undoRefusedAfterGiven() throws {
        let room = try makeRoom()
        let source = PresentationFactory.makeDraft(lesson: room.lesson, students: [room.ada, room.ben], context: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let result = try split([room.ada], off: source, in: room)
        result.destination.state = .presented

        #expect(!PresentationDetailActions().undoSplit(result, context: room.context))
        #expect(source.resolvedStudentIDs == [try #require(room.ben.id)])
    }
}
