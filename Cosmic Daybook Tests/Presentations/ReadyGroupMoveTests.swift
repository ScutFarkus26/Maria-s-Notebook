import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Moving a child between a ready lesson's groups from her chip's menu: to
/// another group, to a new one, out of a group she leaves empty, and back
/// with Undo. Her own records go with her and nothing else is copied.
@Suite("Ready backlog: moving a child between groups")
@MainActor
struct ReadyGroupMoveTests {

    struct Room {
        let context: NSManagedObjectContext
        let ada: CDStudent
        let ben: CDStudent
        let cy: CDStudent
        let lesson: CDLesson
        let other: CDLesson
    }

    func makeRoom() throws -> Room {
        let context = try CoreDataTestHelpers.makeContext()
        let room = Room(
            context: context,
            ada: CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane"),
            ben: CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Ross"),
            cy: CoreDataTestHelpers.seedStudent(in: context, firstName: "Cy", lastName: "Park"),
            lesson: CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads", sequence: "Decimal"),
            other: CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", sequence: "Decimal")
        )
        #expect(CoreDataTestHelpers.save(context))
        return room
    }

    func group(_ lesson: CDLesson, _ students: [CDStudent], in context: NSManagedObjectContext) throws
        -> CDLessonAssignment {
        let group = PresentationFactory.makeDraft(
            lessonID: try #require(lesson.id), studentIDs: try students.map { try #require($0.id) }, context: context
        )
        group.updateDenormalizedKeys()
        return group
    }

    private func promotedEntry(
        for student: CDStudent, into group: CDLessonAssignment, in context: NSManagedObjectContext
    ) throws -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(student.id).uuidString
        entry.lessonID = group.lessonID
        entry.status = .promoted
        entry.promotedAssignmentID = try #require(group.id).uuidString
        return entry
    }

    /// A child's id, outside any `#require` so the macros don't nest.
    func id(_ student: CDStudent) throws -> UUID {
        try #require(student.id)
    }

    private func ids(_ students: [CDStudent]) throws -> Set<String> {
        Set(try students.map { try #require($0.id).uuidString })
    }

    private func groups(_ context: NSManagedObjectContext) -> [CDLessonAssignment] {
        context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
    }

    // MARK: - To an existing group

    @Test("Moving to another group changes both rosters and takes her year-plan entry along")
    func moveToExistingGroup() throws {
        let room = try makeRoom()
        let source = try group(room.lesson, [room.ada, room.ben], in: room.context)
        let target = try group(room.lesson, [room.cy], in: room.context)
        let adasEntry = try promotedEntry(for: room.ada, into: source, in: room.context)
        let bensEntry = try promotedEntry(for: room.ben, into: source, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let receipt = try #require(
            PresentationGroupMove.move(try id(room.ada), from: source, to: target, in: room.context)
        )
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(Set(source.studentIDs) == (try ids([room.ben])))
        #expect(Set(target.studentIDs) == (try ids([room.cy, room.ada])))
        #expect(adasEntry.promotedAssignmentID == target.id?.uuidString)
        #expect(bensEntry.promotedAssignmentID == source.id?.uuidString)
        #expect(receipt.createdTarget == false)
        #expect(receipt.deletedSource == nil)
        #expect(groups(room.context).count == 2)
    }

    @Test("A move between two different lessons, or onto a group she is already on, changes nothing")
    func refusedMoves() throws {
        let room = try makeRoom()
        let source = try group(room.lesson, [room.ada, room.ben], in: room.context)
        let otherLesson = try group(room.other, [room.cy], in: room.context)
        let alreadyThere = try group(room.lesson, [room.ada], in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let ada = try id(room.ada)

        #expect(PresentationGroupMove.move(ada, from: source, to: otherLesson, in: room.context) == nil)
        #expect(PresentationGroupMove.move(ada, from: source, to: alreadyThere, in: room.context) == nil)
        #expect(PresentationGroupMove.move(ada, from: source, to: source, in: room.context) == nil)
        #expect(room.context.hasChanges == false)
    }

    // MARK: - To a new group

    @Test("Moving to a new group makes a planned group of the same lesson with only the lesson's fields")
    func moveToNewGroup() throws {
        let room = try makeRoom()
        let source = try group(room.lesson, [room.ada, room.ben], in: room.context)
        source.lessonTitleSnapshot = "Golden Beads"
        source.lessonSectionSnapshot = "Decimal"
        source.trackID = "track-1"
        source.trackStepID = "step-1"
        source.manuallyUnblocked = true
        source.notes = "Bring the bead frame"
        source.followUpWork = "Practice exchanges"
        source.needsPractice = true
        CoreDataTestHelpers.seedNote(in: room.context, body: "Ben counted to a thousand").lessonAssignment = source
        let adasEntry = try promotedEntry(for: room.ada, into: source, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let receipt = try #require(
            PresentationGroupMove.moveToNewGroup(try id(room.ada), from: source, in: room.context)
        )
        #expect(CoreDataTestHelpers.save(room.context))

        let made = try #require(room.context.object(CDLessonAssignment.self, id: receipt.targetID))
        #expect(receipt.createdTarget)
        #expect(made.state == .draft)
        #expect(made.scheduledFor == nil)
        #expect(made.lessonID == source.lessonID)
        #expect(made.studentIDs == [try id(room.ada).uuidString])
        #expect(made.lessonTitleSnapshot == "Golden Beads")
        #expect(made.lessonSectionSnapshot == "Decimal")
        #expect(made.trackID == "track-1")
        #expect(made.trackStepID == "step-1")
        #expect(made.manuallyUnblocked)
        // Nothing that belongs to the source's own sitting comes along.
        #expect(made.notes.isEmpty)
        #expect(made.followUpWork.isEmpty)
        #expect(made.needsPractice == false)
        #expect((made.unifiedNotes?.count ?? 0) == 0)
        #expect(source.unifiedNotes?.count == 1)
        #expect(Set(source.studentIDs) == (try ids([room.ben])))
        #expect(adasEntry.promotedAssignmentID == made.id?.uuidString)
    }

    @Test("A lone child is not moved into a new group of her own")
    func loneChildHasNoNewGroup() throws {
        let room = try makeRoom()
        let source = try group(room.lesson, [room.ada], in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(PresentationGroupMove.moveToNewGroup(try id(room.ada), from: source, in: room.context) == nil)
        #expect(room.context.hasChanges == false)
    }

    // MARK: - Emptying the source

    @Test("A group left empty is deleted, and its notes go to the group she joined")
    func emptiedSourceIsDeleted() throws {
        let room = try makeRoom()
        let source = try group(room.lesson, [room.ada], in: room.context)
        let target = try group(room.lesson, [room.ben], in: room.context)
        let note = CoreDataTestHelpers.seedNote(in: room.context, body: "Ada is ready for exchanges")
        note.lessonAssignment = source
        let entry = try promotedEntry(for: room.ada, into: source, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let sourceID = try #require(source.id)

        let receipt = try #require(
            PresentationGroupMove.move(try id(room.ada), from: source, to: target, in: room.context)
        )
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(room.context.object(CDLessonAssignment.self, id: sourceID) == nil)
        #expect(groups(room.context).count == 1)
        #expect(note.lessonAssignment == target)
        #expect(entry.promotedAssignmentID == target.id?.uuidString)
        #expect(receipt.deletedSource != nil)
    }

    // MARK: - Undo

    @Test("Undo puts her back in the group she came from")
    func undoMoveToExistingGroup() throws {
        let room = try makeRoom()
        let source = try group(room.lesson, [room.ada, room.ben], in: room.context)
        let target = try group(room.lesson, [room.cy], in: room.context)
        let entry = try promotedEntry(for: room.ada, into: source, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let receipt = try #require(
            PresentationGroupMove.move(try id(room.ada), from: source, to: target, in: room.context)
        )
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(PresentationGroupMove.undo(receipt, in: room.context))
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(Set(source.studentIDs) == (try ids([room.ada, room.ben])))
        #expect(Set(target.studentIDs) == (try ids([room.cy])))
        #expect(entry.promotedAssignmentID == source.id?.uuidString)
    }

    @Test("Undo of a move to a new group deletes the new group")
    func undoMoveToNewGroup() throws {
        let room = try makeRoom()
        let source = try group(room.lesson, [room.ada, room.ben], in: room.context)
        let entry = try promotedEntry(for: room.ada, into: source, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let receipt = try #require(
            PresentationGroupMove.moveToNewGroup(try id(room.ada), from: source, in: room.context)
        )
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(PresentationGroupMove.undo(receipt, in: room.context))
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(room.context.object(CDLessonAssignment.self, id: receipt.targetID) == nil)
        #expect(groups(room.context).count == 1)
        #expect(Set(source.studentIDs) == (try ids([room.ada, room.ben])))
        #expect(entry.promotedAssignmentID == source.id?.uuidString)
    }

    @Test("Undo rebuilds an emptied group with its own id and fields, and gives its notes back")
    func undoRebuildsEmptiedGroup() throws {
        let room = try makeRoom()
        let source = try group(room.lesson, [room.ada], in: room.context)
        source.notes = "Bring the bead frame"
        source.manuallyUnblocked = true
        let target = try group(room.lesson, [room.ben], in: room.context)
        let targetNote = CoreDataTestHelpers.seedNote(in: room.context, body: "Ben's own note")
        targetNote.lessonAssignment = target
        let sourceNote = CoreDataTestHelpers.seedNote(in: room.context, body: "Ada is ready for exchanges")
        sourceNote.lessonAssignment = source
        let entry = try promotedEntry(for: room.ada, into: source, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let sourceID = try #require(source.id)
        let receipt = try #require(
            PresentationGroupMove.move(try id(room.ada), from: source, to: target, in: room.context)
        )
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(PresentationGroupMove.undo(receipt, in: room.context))
        #expect(CoreDataTestHelpers.save(room.context))

        let rebuilt = try #require(room.context.object(CDLessonAssignment.self, id: sourceID))
        #expect(rebuilt.studentIDs == [try id(room.ada).uuidString])
        #expect(rebuilt.lessonID == target.lessonID)
        #expect(rebuilt.notes == "Bring the bead frame")
        #expect(rebuilt.manuallyUnblocked)
        #expect(rebuilt.state == .draft)
        #expect(sourceNote.lessonAssignment == rebuilt)
        #expect(targetNote.lessonAssignment == target)
        #expect(Set(target.studentIDs) == (try ids([room.ben])))
        #expect(entry.promotedAssignmentID == sourceID.uuidString)
        #expect(groups(room.context).count == 2)
    }

    @Test("Undo changes nothing once she has moved on again")
    func undoRefusedAfterLaterMove() throws {
        let room = try makeRoom()
        let source = try group(room.lesson, [room.ada, room.ben], in: room.context)
        let target = try group(room.lesson, [room.cy], in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let ada = try id(room.ada)
        let receipt = try #require(PresentationGroupMove.move(ada, from: source, to: target, in: room.context))
        #expect(CoreDataTestHelpers.save(room.context))
        target.studentIDs.removeAll { $0 == ada.uuidString }
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(PresentationGroupMove.undo(receipt, in: room.context) == false)
        #expect(room.context.hasChanges == false)
    }
}
