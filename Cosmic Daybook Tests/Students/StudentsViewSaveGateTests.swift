import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Students roster refreshes its signals after each burst of saves while
/// it is on screen. The gate drops saves that touch none of the tables a
/// signal is read from, which cannot move one.
@Suite("Students roster save gate")
@MainActor
struct StudentsViewSaveGateTests {

    @Test("The gate watches the tables the signals read: the table caches plus attendance")
    func watchesTheSignalTables() throws {
        // A stack first, so `CDFetchRequest` resolves names from the app's model.
        _ = try CoreDataTestHelpers.makeContext()
        let names = Set([
            CDFetchRequest(CDAttendanceRecord.self).entityName,
            CDFetchRequest(CDLessonAssignment.self).entityName,
            CDFetchRequest(CDLesson.self).entityName,
            CDFetchRequest(CDStudent.self).entityName,
            CDFetchRequest(CDNote.self).entityName
        ].compactMap { $0 })
        #expect(names.count == 5)
        #expect(names.isSubset(of: StudentsViewModel.signalInputEntities))
        #expect(StudentsViewModel.signalInputEntities
            == StudentsViewModel.tableCacheInputEntities.union(["AttendanceRecord"]))
    }

    @Test("Saves of other tables are dropped; a save touching a signal table passes")
    func gateOnPayloads() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let attendance = CoreDataTestHelpers.seedAttendance(in: context)
        let assignment = CDLessonAssignment(context: context)
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let student = CoreDataTestHelpers.seedStudent(in: context)
        let work = CoreDataTestHelpers.seedWorkModel(in: context)
        let note = CoreDataTestHelpers.seedNote(in: context)

        #expect(StudentsView.saveTouchesSignals([
            NSInsertedObjectsKey: Set<NSManagedObject>([work])
        ]) == false)
        #expect(StudentsView.saveTouchesSignals([
            NSDeletedObjectsKey: Set<NSManagedObject>([work])
        ]) == false)
        #expect(StudentsView.saveTouchesSignals([
            NSUpdatedObjectsKey: Set<NSManagedObject>([attendance])
        ]) == true)
        #expect(StudentsView.saveTouchesSignals([
            NSInsertedObjectsKey: Set<NSManagedObject>([assignment])
        ]) == true)
        #expect(StudentsView.saveTouchesSignals([
            NSDeletedObjectsKey: Set<NSManagedObject>([lesson])
        ]) == true)
        // A note is an observation, and a student's next-lesson pick lives on her row.
        #expect(StudentsView.saveTouchesSignals([
            NSInsertedObjectsKey: Set<NSManagedObject>([note])
        ]) == true)
        #expect(StudentsView.saveTouchesSignals([
            NSUpdatedObjectsKey: Set<NSManagedObject>([student])
        ]) == true)
        // Unknown shapes fail open, as the unscoped listener did.
        #expect(StudentsView.saveTouchesSignals(nil) == true)
        #expect(StudentsView.saveTouchesSignals([:]) == true)
    }

    @Test("Real save notifications are judged by what each save wrote")
    func gateOnRealSaves() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let verdicts = VerdictBox()
        let token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: context, queue: nil
        ) { note in
            verdicts.values.append(StudentsView.saveTouchesSignals(note.userInfo))
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // Work alone: nothing a signal reads.
        CoreDataTestHelpers.seedWorkModel(in: context)
        #expect(CoreDataTestHelpers.save(context))
        // A new attendance row, then a status flip on it.
        let attendance = CoreDataTestHelpers.seedAttendance(in: context)
        #expect(CoreDataTestHelpers.save(context))
        attendance.statusRaw = AttendanceStatus.present.rawValue
        attendance.modifiedAt = Date()
        #expect(CoreDataTestHelpers.save(context))
        // An observation.
        CoreDataTestHelpers.seedNote(in: context, body: "Counted to 100")
        #expect(CoreDataTestHelpers.save(context))

        #expect(verdicts.values == [false, true, true, true])
    }
}

/// Posted synchronously on the test's own thread (queue: nil), so no locking.
/// Nonisolated so the observer's `@Sendable` block can append to it.
private nonisolated final class VerdictBox: @unchecked Sendable {
    var values: [Bool] = []
}
