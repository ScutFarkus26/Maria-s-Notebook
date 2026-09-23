import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins that the per-object memo behind `studentIDs` / `confirmedStudentIDs`
/// always reports what the raw attribute currently holds.
@MainActor
struct LessonAssignmentStudentIDsMemoTests {

    private func decoded(_ data: Data?) -> [String] {
        CloudKitStringArrayStorage.decode(from: data)
    }

    @Test func tracksSetterAndRawWrites() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let la = CDLessonAssignment(context: context)
        #expect(la.studentIDs == [])

        la.studentIDs = ["a", "b"]
        #expect(la.studentIDs == ["a", "b"])

        // A write straight to the raw attribute (as backup import does).
        la._studentIDsData = CloudKitStringArrayStorage.encode(["c"])
        #expect(la.studentIDs == ["c"])
        #expect(la.studentIDs == decoded(la._studentIDsData))

        la._studentIDsData = nil
        #expect(la.studentIDs == [])

        la.confirmedStudentIDs = ["x"]
        #expect(la.confirmedStudentIDs == ["x"])
        la._confirmedStudentIDsData = CloudKitStringArrayStorage.encode(["y", "z"])
        #expect(la.confirmedStudentIDs == ["y", "z"])
    }

    @Test func tracksMergeFromAnotherContext() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let viewContext = stack.viewContext
        let la = CDLessonAssignment(context: viewContext)
        la.studentIDs = ["a"]
        la.confirmedStudentIDs = ["a"]
        try viewContext.save()
        #expect(la.studentIDs == ["a"])
        #expect(la.confirmedStudentIDs == ["a"])

        let other = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        other.persistentStoreCoordinator = viewContext.persistentStoreCoordinator
        let otherCopy = try #require(other.existingObject(with: la.objectID) as? CDLessonAssignment)
        otherCopy.studentIDs = ["a", "b"]
        otherCopy.confirmedStudentIDs = ["b"]
        try other.save()

        viewContext.refresh(la, mergeChanges: true)
        #expect(la.studentIDs == ["a", "b"])
        #expect(la.confirmedStudentIDs == ["b"])

        // Refault without merge, then another remote change.
        otherCopy.studentIDs = ["c"]
        try other.save()
        viewContext.refresh(la, mergeChanges: false)
        #expect(la.studentIDs == ["c"])
    }

    @Test func tracksUndo() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let undo = UndoManager()
        undo.groupsByEvent = false
        context.undoManager = undo

        undo.beginUndoGrouping()
        let la = CDLessonAssignment(context: context)
        la.studentIDs = ["a"]
        undo.endUndoGrouping()
        context.processPendingChanges()
        #expect(la.studentIDs == ["a"])

        undo.beginUndoGrouping()
        la.studentIDs = ["a", "b"]
        undo.endUndoGrouping()
        context.processPendingChanges()
        #expect(la.studentIDs == ["a", "b"])

        undo.undo()
        context.processPendingChanges()
        #expect(la.studentIDs == ["a"])

        undo.redo()
        context.processPendingChanges()
        #expect(la.studentIDs == ["a", "b"])
    }

    @Test func tracksRollback() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let la = CDLessonAssignment(context: context)
        la.studentIDs = ["a"]
        try context.save()
        la.studentIDs = ["a", "b"]
        #expect(la.studentIDs == ["a", "b"])
        context.rollback()
        #expect(la.studentIDs == ["a"])
    }
}
