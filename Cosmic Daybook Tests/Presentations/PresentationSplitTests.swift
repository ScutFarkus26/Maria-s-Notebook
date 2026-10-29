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
        _ moving: [CDStudent], off source: CDLessonAssignment, in room: Room,
        sheetRoster: [CDStudent] = []
    ) throws -> PresentationSplit {
        let split = PresentationDetailActions().moveStudentsToInbox(
            from: source,
            currentLesson: room.lesson,
            studentsToMove: Set(try moving.map { try #require($0.id) }),
            studentsAll: [room.ada, room.ben, room.cy],
            lessonAssignmentsAll: plans(room.context),
            keepOnSource: Set(try sheetRoster.map { try #require($0.id) }),
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

    @Test("Undo leaves off the saved plan a child who was only added in the open sheet")
    func undoLeavesOffChildAddedInSheet() throws {
        let room = try makeRoom()
        let source = PresentationFactory.makeDraft(lesson: room.lesson, students: [room.ada, room.ben], context: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        // Cy is on the sheet's roster but not yet saved on the plan.
        let result = try split([room.cy], off: source, in: room)
        #expect(result.wereOnSource.isEmpty)
        #expect(PresentationDetailActions().undoSplit(result, context: room.context))
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(Set(source.resolvedStudentIDs) == Set(try [room.ada, room.ben].map { try #require($0.id) }))
        #expect(plans(room.context) == [source])
    }

    @Test("Undo on a new presentation leaves it empty, so Cancel still throws it away")
    func undoOnNewPresentationLeavesItEmpty() throws {
        let room = try makeRoom()
        // What File › New makes: a placeholder lesson and no children, saved,
        // with the lesson and children picked in the sheet.
        let source = PresentationFactory.makeDraft(lessonID: UUID(), studentIDs: [], context: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let result = try split([room.ada], off: source, in: room)
        #expect(PresentationDetailActions().undoSplit(result, context: room.context))
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(source.studentIDs.isEmpty)
        #expect(plans(room.context) == [source])
    }

    @Test("Splitting off every saved child keeps the sheet's other children on the plan, and its notes with it")
    func splitOfEverySavedChildKeepsSheetChildren() throws {
        let room = try makeRoom()
        let source = PresentationFactory.makeDraft(lesson: room.lesson, students: [room.ada, room.ben], context: room.context)
        let groupNote = CoreDataTestHelpers.seedNote(in: room.context, body: "Whole group")
        groupNote.lessonAssignment = source
        #expect(CoreDataTestHelpers.save(room.context))

        // Cy was added in the sheet; Ada and Ben, the plan's saved children, go.
        let result = try split([room.ada, room.ben], off: source, in: room, sheetRoster: [room.ada, room.ben, room.cy])
        let cyID = try #require(room.cy.id)

        // Not left empty, so Cancel keeps the plan and its note.
        #expect(source.resolvedStudentIDs == [cyID])
        #expect(result.keptOnSource == [cyID])
        #expect(groupNote.lessonAssignment == source)

        #expect(PresentationDetailActions().undoSplit(result, context: room.context))
        #expect(CoreDataTestHelpers.save(room.context))
        #expect(Set(source.resolvedStudentIDs) == Set(try [room.ada, room.ben].map { try #require($0.id) }))
        #expect(plans(room.context) == [source])
    }

    @Test("A split leaves a new presentation's sheet children unsaved, so Cancel still throws it away")
    func splitLeavesNewPresentationEmpty() throws {
        let room = try makeRoom()
        let source = PresentationFactory.makeDraft(lessonID: UUID(), studentIDs: [], context: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let result = try split([room.ada], off: source, in: room, sheetRoster: [room.ada, room.ben])

        #expect(source.studentIDs.isEmpty)
        #expect(result.keptOnSource.isEmpty)
    }

    @Test("A split uses the lesson the plan is saved with, not an unsaved Change Lesson")
    func splitUsesSavedLesson() throws {
        let room = try makeRoom()
        let other = CoreDataTestHelpers.seedLesson(in: room.context, name: "Subtraction", sequence: "Fractions")
        let source = PresentationFactory.makeDraft(lesson: room.lesson, students: [room.ada, room.ben], context: room.context)
        let fresh = PresentationFactory.makeDraft(lessonID: UUID(), studentIDs: [], context: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let lessons = [room.lesson, other]

        #expect(PresentationDetailActions.splitLesson(for: source, edited: other, lessons: lessons) == room.lesson)
        // A new presentation has no saved lesson, so the one picked in the sheet.
        #expect(PresentationDetailActions.splitLesson(for: fresh, edited: other, lessons: lessons) == other)
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
