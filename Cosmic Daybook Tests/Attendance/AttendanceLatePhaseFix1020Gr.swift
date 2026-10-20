import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Daybook Assistant bug hunt 2026-10-20, #2 and #5, on the notebook's roll:
/// arrival closed on an assistant's phone read as open here once its
/// automatic absences were resolved, and a Close Arrival made here held
/// after the same children's absences were undone on another device.
@Suite("Attendance roll: the Late phase (Fix1020 Gr)")
@MainActor
struct AttendanceLatePhaseFix1020GrTests {

    private let stack: CoreDataStack
    private let defaults: UserDefaults
    private let today = AppCalendar.startOfDay(Date())

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        let suite = "AttendanceLatePhaseFix1020GrTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    private func student(_ first: String) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = first
        student.lastName = "Stone"
        student.dateStarted = Calendar.current.date(byAdding: .year, value: -1, to: today)
        return student
    }

    private func roll(_ students: [CDStudent]) -> AttendanceViewModel {
        let roll = AttendanceViewModel(selectedDate: today, defaults: defaults)
        roll.load(students: students, modelContext: context)
        return roll
    }

    private func record(of student: CDStudent) throws -> CDAttendanceRecord {
        try #require(try CDAttendanceStore(context: context).loadRecords(for: today).first {
            $0.studentID == student.id?.uuidString
        })
    }

    @Test("Closed on a phone: the roll stays Late once the absences are resolved")
    func lateHoldsHere() throws {
        let maya = student("Maya"), ari = student("Ari")
        let phone = CDAttendanceStore(context: context, role: .assistant)
        #expect(try phone.markUnmarkedAbsent(for: today, students: [maya, ari]).count == 2)
        try context.save()
        let roll = roll([maya, ari])
        #expect(roll.phase == .late)

        #expect(phone.updateStatus(try record(of: maya), to: .tardy))
        #expect(phone.updateAbsenceReason(try record(of: ari), to: .sick))
        try context.save()
        roll.load(students: [maya, ari], modelContext: context)
        #expect(roll.phase == .late)
        #expect(try CDAttendanceStore(context: context).arrivalClosed(on: today, defaults: defaults))
    }

    @Test("Closed here, then the same children's absences undone on a phone: back to Arrival")
    func undoElsewhereReopensHere() throws {
        let maya = student("Maya"), ari = student("Ari")
        let roll = roll([maya, ari])
        #expect(roll.closeArrival(modelContext: context)?.records.count == 2)
        try context.save()
        #expect(roll.phase == .late)

        let phone = CDAttendanceStore(context: context, role: .assistant)
        for child in [maya, ari] { #expect(phone.undoAutomaticAbsence(try record(of: child))) }
        try context.save()
        roll.load(students: [maya, ari], modelContext: context)
        #expect(roll.phase == .arrival)
    }
}
