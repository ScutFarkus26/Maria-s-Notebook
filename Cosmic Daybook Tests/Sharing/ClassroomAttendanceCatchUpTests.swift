import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What the Mac's one-time "Add This Year's Attendance to the Share" takes:
/// this school year's attendance in the guide's private store that belongs in
/// the share and is in no share yet, and nothing else. The step itself runs
/// only on the Mac; its choice is tested here (2026-10-05).
@Suite("Adding this year's attendance to the share")
@MainActor
struct ClassroomAttendanceCatchUpTests {

    @Test("Only this school year's marks, of children who belong, in the private store")
    func takesThisYearsMarksOnly() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let privateStore = try stack.container.persistentStoreCoordinator.addPersistentStore(
            type: .inMemory,
            configuration: CoreDataStack.privateConfiguration,
            at: URL(fileURLWithPath: "/dev/null/private-\(UUID().uuidString)")
        )
        let unified = try #require(stack.container.persistentStoreCoordinator.persistentStores.first)
        let context = stack.viewContext
        let cutoff = AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: 810_000_000))
        func student(left: Date? = nil) -> CDStudent {
            let student = CDStudent(context: context)
            student.id = UUID()
            if let left {
                student.enrollmentStatus = .withdrawn
                student.dateWithdrawn = left
            }
            context.assign(student, to: privateStore)
            return student
        }
        func mark(_ student: CDStudent, _ days: Double, in store: NSPersistentStore) -> CDAttendanceRecord {
            let record = CDAttendanceRecord(context: context)
            record.studentID = student.id?.uuidString ?? ""
            record.date = cutoff.addingTimeInterval(days * 86_400)
            context.assign(record, to: store)
            return record
        }
        let maya = student()
        let leftLastYear = student(left: cutoff.addingTimeInterval(-100 * 86_400))
        let thisYear = mark(maya, 5, in: privateStore)
        _ = mark(maya, -30, in: privateStore) // last year's
        _ = mark(maya, 6, in: unified) // not the guide's private store
        _ = mark(leftLastYear, -120, in: privateStore)
        #expect(context.safeSave())

        let waiting = try await ClassroomAttendanceCatchUp.waiting(
            storeID: privateStore.identifier, container: stack.container, scope: ClassroomShareScope(cutoff: cutoff)
        )
        #expect(waiting == [thisYear.objectID])
    }

    @Test("The count and the result read plainly")
    func wording() {
        let one = ClassroomAttendanceCatchUp.title(waiting: 1)
        #expect(one == "1 attendance mark from this school year isn't in the share")
        let many = ClassroomAttendanceCatchUp.title(waiting: 1_204)
        #expect(many == "1,204 attendance marks from this school year aren't in the share")
        let report = ClassroomAttendanceCatchUp.Report(
            attached: 12, failed: 2, stoppedBecause: "iCloud stopped syncing"
        )
        #expect(report.summary == "Added 12 attendance marks to the share. "
            + "2 couldn't be added because iCloud stopped syncing. Try again later.")
    }
}
