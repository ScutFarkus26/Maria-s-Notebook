import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

// Coverage for the multi-user attendance groundwork: records are created lazily
// on the first mark (never in bulk on screen-open), every mutation stamps who
// made it, and the permission matrix actually gates assistant writes.
@Suite("Attendance store attribution & lazy creation")
@MainActor
struct AttendanceStoreAttributionTests {

    private func makeStudent(in context: NSManagedObjectContext) -> CDStudent {
        let student = CDStudent(context: context)
        student.firstName = "Etty"
        student.lastName = "Example"
        return student
    }

    @Test("Loading a day creates nothing; the first mark creates exactly one record")
    func createOnFirstMark() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = makeStudent(in: context)
        let day = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context)

        #expect(try store.loadRecords(for: day).isEmpty)
        #expect(context.insertedObjects.filter { $0 is CDAttendanceRecord }.isEmpty)

        let first = try #require(try store.ensureRecord(for: student, on: day))
        let second = try #require(try store.ensureRecord(for: student, on: day))
        #expect(first === second)
        #expect(try store.loadRecords(for: day).count == 1)
    }

    @Test("Mutations stamp recordedBy and modifiedAt; no-op mutations don't")
    func attributionStamping() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = makeStudent(in: context)
        let day = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context)

        let record = try #require(try store.ensureRecord(for: student, on: day))
        // No membership row → this device is its own lead guide.
        #expect(record.recordedBy == CDClassroomMembership.ClassroomRole.leadGuide.rawValue)
        let createdStamp = try #require(record.modifiedAt)

        #expect(store.updateStatus(record, to: .tardy))
        let markedStamp = try #require(record.modifiedAt)
        #expect(markedStamp >= createdStamp)

        // Same status again: no change, stamp untouched.
        #expect(!store.updateStatus(record, to: .tardy))
        #expect(record.modifiedAt == markedStamp)
    }

    @Test("An assistant can write attendance only while the category is enabled")
    func assistantPermissionGate() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = makeStudent(in: context)
        let day = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context, role: .assistant)

        let saved = SharingPreferences.assistantWritableCategories()
        defer { SharingPreferences.setAssistantWritableCategories(saved) }

        SharingPreferences.setAssistantWritableCategories([.attendance])
        let record = try #require(try store.ensureRecord(for: student, on: day))
        #expect(store.updateStatus(record, to: .present))
        #expect(record.recordedBy == CDClassroomMembership.ClassroomRole.assistant.rawValue)

        SharingPreferences.setAssistantWritableCategories([])
        #expect(!store.updateStatus(record, to: .absent))
        #expect(record.status == .present)
        #expect(try store.ensureRecord(for: student, on: AppCalendar.addingDays(1, to: day)) == nil)
    }

    @Test("markAllPresent stamps only the records it actually changes")
    func markAllPresentStampsChanges() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let studentA = makeStudent(in: context)
        let studentB = makeStudent(in: context)
        let day = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context)

        let existing = try #require(try store.ensureRecord(for: studentA, on: day))
        #expect(store.updateStatus(existing, to: .present))
        let priorStamp = existing.modifiedAt

        let records = try store.markAllPresent(for: day, students: [studentA, studentB])
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.status == .present })
        // Already-present record untouched; the new one stamped.
        #expect(existing.modifiedAt == priorStamp)
        let created = try #require(records.first { $0 !== existing })
        #expect(created.modifiedAt != nil)
    }
}
