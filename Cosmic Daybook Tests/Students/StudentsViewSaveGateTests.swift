import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Students roster refreshes three change tokens after each burst of saves
/// while it is on screen. It used to do that after a save of anything; the gate
/// drops saves that touch none of the tables the tokens are read from, which
/// cannot move a token.
@Suite("Students roster save gate")
@MainActor
struct StudentsViewSaveGateTests {

    @Test("The gate watches exactly the tables refreshChangeTokens reads")
    func watchesTheTokenTables() throws {
        // A stack first, so `CDFetchRequest` resolves names from the app's model.
        _ = try CoreDataTestHelpers.makeContext()
        let tokenTables = Set([
            CDFetchRequest(CDAttendanceRecord.self).entityName,
            CDFetchRequest(CDLessonAssignment.self).entityName,
            CDFetchRequest(CDLesson.self).entityName
        ].compactMap { $0 })
        #expect(tokenTables.count == 3)
        #expect(StudentsView.changeTokenEntityNames == tokenTables)
    }

    @Test("Saves of other tables are dropped; a save touching a token table passes")
    func gateOnPayloads() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let attendance = CoreDataTestHelpers.seedAttendance(in: context)
        let assignment = CDLessonAssignment(context: context)
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let student = CoreDataTestHelpers.seedStudent(in: context)
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        let note = CoreDataTestHelpers.seedNote(in: context)

        #expect(StudentsView.saveTouchesChangeTokens([
            NSInsertedObjectsKey: Set<NSManagedObject>([student, work, note])
        ]) == false)
        #expect(StudentsView.saveTouchesChangeTokens([
            NSUpdatedObjectsKey: Set<NSManagedObject>([note]),
            NSDeletedObjectsKey: Set<NSManagedObject>([work])
        ]) == false)
        #expect(StudentsView.saveTouchesChangeTokens([
            NSUpdatedObjectsKey: Set<NSManagedObject>([attendance])
        ]) == true)
        #expect(StudentsView.saveTouchesChangeTokens([
            NSInsertedObjectsKey: Set<NSManagedObject>([assignment])
        ]) == true)
        #expect(StudentsView.saveTouchesChangeTokens([
            NSDeletedObjectsKey: Set<NSManagedObject>([lesson])
        ]) == true)
        #expect(StudentsView.saveTouchesChangeTokens([
            NSInsertedObjectsKey: Set<NSManagedObject>([note]),
            NSUpdatedObjectsKey: Set<NSManagedObject>([lesson])
        ]) == true)
        // Unknown shapes fail open, as the unscoped listener did.
        #expect(StudentsView.saveTouchesChangeTokens(nil) == true)
        #expect(StudentsView.saveTouchesChangeTokens([:]) == true)
    }

    @Test("Real save notifications are judged by what each save wrote")
    func gateOnRealSaves() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let verdicts = VerdictBox()
        let token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: context, queue: nil
        ) { note in
            verdicts.values.append(StudentsView.saveTouchesChangeTokens(note.userInfo))
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // A note and a new child: nothing the tokens count.
        CoreDataTestHelpers.seedNote(in: context, body: "Unrelated")
        CoreDataTestHelpers.seedStudent(in: context)
        #expect(CoreDataTestHelpers.save(context))
        // A new attendance row, then a status flip on it.
        let attendance = CoreDataTestHelpers.seedAttendance(in: context)
        #expect(CoreDataTestHelpers.save(context))
        attendance.statusRaw = AttendanceStatus.present.rawValue
        attendance.modifiedAt = Date()
        #expect(CoreDataTestHelpers.save(context))
        // A presentation next to an unrelated edit.
        CoreDataTestHelpers.seedNote(in: context, body: "Also unrelated")
        _ = CDLessonAssignment(context: context)
        #expect(CoreDataTestHelpers.save(context))

        #expect(verdicts.values == [false, true, true, true])
    }
}

/// Posted synchronously on the test's own thread (queue: nil), so no locking.
/// Nonisolated so the observer's `@Sendable` block can append to it.
private nonisolated final class VerdictBox: @unchecked Sendable {
    var values: [Bool] = []
}
