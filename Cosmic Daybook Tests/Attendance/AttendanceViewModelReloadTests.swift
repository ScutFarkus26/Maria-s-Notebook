import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// An import that changes a record already on screen hands the roll back the
// same objects, so the records dictionary compares equal and Observation would
// skip the redraw. `loadGeneration` moves on every load so the grid redraws.
@Suite("Attendance roll reload")
@MainActor
struct AttendanceViewModelReloadTests {

    @Test("Reloading the same records still moves the generation")
    func sameRecordsStillMoveTheGeneration() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = "Chaviva"
        student.lastName = "Example"
        let day = AppCalendar.startOfDay(Date())
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: student, on: day))
        #expect(store.updateStatus(record, to: .present))
        try context.save()

        let viewModel = AttendanceViewModel(selectedDate: day)
        viewModel.load(students: [student], modelContext: context)
        let before = viewModel.recordsByStudentID
        let generation = viewModel.loadGeneration

        // Another device changes the same record; the reload returns the same object.
        record.status = .tardy
        viewModel.load(students: [student], modelContext: context)

        #expect(viewModel.recordsByStudentID == before)
        #expect(viewModel.loadGeneration == generation &+ 1)
        #expect(viewModel.recordsByStudentID[student.cloudKitKey]?.status == .tardy)
    }
}
