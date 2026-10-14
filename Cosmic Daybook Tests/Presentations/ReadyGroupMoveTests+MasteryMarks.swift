import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A move never loses a mastery or proficiency mark (2026-10-14 review): the
/// group she leaves, or one she empties, had its history rows deleted, marks
/// and all, and Undo couldn't bring them back. They are kept as marks of
/// their own, as Remove Plan keeps them.
/// Split from ReadyGroupMoveTests.swift for SwiftLint's type-length limit.
extension ReadyGroupMoveTests {

    private func markRow(
        for student: CDStudent, on group: CDLessonAssignment, proficient: Bool = false,
        in context: NSManagedObjectContext
    ) throws -> CDLessonPresentation {
        let row = CDLessonPresentation(context: context)
        row.studentID = try #require(student.id).uuidString
        row.lessonID = group.lessonID
        row.presentationID = try #require(group.id).uuidString
        row.presentedAt = Date()
        if proficient {
            row.state = .proficient
        } else {
            row.masteredAt = Date()
        }
        return row
    }

    private func liveRows(_ context: NSManagedObjectContext) -> [CDLessonPresentation] {
        context.safeFetch(CDFetchRequest(CDLessonPresentation.self)).filter { !$0.isDeleted }
    }

    @Test("Moving a child keeps her mastery and proficiency marks from the group she left, through Undo")
    func moveKeepsMasteryMarks() throws {
        let room = try makeRoom()
        let source = try group(room.lesson, [room.ada, room.ben], in: room.context)
        let target = try group(room.lesson, [room.cy], in: room.context)
        let adasMark = try markRow(for: room.ada, on: source, in: room.context)
        let adasProficient = try markRow(for: room.ada, on: source, proficient: true, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let receipt = try #require(
            PresentationGroupMove.move(try id(room.ada), from: source, to: target, in: room.context)
        )
        #expect(CoreDataTestHelpers.save(room.context))
        #expect(adasMark.isDeleted == false)
        #expect(adasMark.masteredAt != nil)
        #expect(adasProficient.isDeleted == false)
        #expect(adasProficient.state == .proficient)
        #expect(liveRows(room.context).count == 2)

        #expect(PresentationGroupMove.undo(receipt, in: room.context))
        #expect(CoreDataTestHelpers.save(room.context))
        #expect(adasMark.isDeleted == false)
        #expect(adasMark.masteredAt != nil)
        #expect(adasProficient.isDeleted == false)
        #expect(liveRows(room.context).count == 2)
    }

    @Test("Emptying a group keeps every mastery mark filed on it, through Undo")
    func emptyingKeepsMasteryMarks() throws {
        let room = try makeRoom()
        let source = try group(room.lesson, [room.ada], in: room.context)
        let target = try group(room.lesson, [room.ben], in: room.context)
        let adasMark = try markRow(for: room.ada, on: source, in: room.context)
        // A mark left on the group by a child taken off it earlier.
        let cysMark = try markRow(for: room.cy, on: source, proficient: true, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let receipt = try #require(
            PresentationGroupMove.move(try id(room.ada), from: source, to: target, in: room.context)
        )
        #expect(CoreDataTestHelpers.save(room.context))
        #expect(receipt.deletedSource != nil)
        #expect(adasMark.isDeleted == false)
        #expect(adasMark.masteredAt != nil)
        #expect(cysMark.isDeleted == false)
        #expect(cysMark.state == .proficient)

        #expect(PresentationGroupMove.undo(receipt, in: room.context))
        #expect(CoreDataTestHelpers.save(room.context))
        #expect(adasMark.isDeleted == false)
        #expect(cysMark.isDeleted == false)
        #expect(liveRows(room.context).count == 2)
    }
}
