import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The notebook's side of the fix round after review (a) of the Daybook
// Assistant's 2026-10-20 fixes: a Close Arrival made on the roll and a phone
// that looks in between the changes remember the same children (2), and
// Reopen Arrival keeps them, with Close Arrival still on offer as the way
// back to Late (3).
@Suite("Attendance fixes 2026-10-20: review (a) round, the Late rule")
@MainActor
struct AttendanceFix1020RoundA2 {

    private let stack: CoreDataStack
    private let defaults: UserDefaults
    /// What an assistant's phone remembers.
    private let phoneDefaults: UserDefaults
    private let today = AppCalendar.startOfDay(Date())

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        let suite = "AttendanceFix1020RoundA2.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let phoneSuite = suite + ".phone"
        phoneDefaults = try #require(UserDefaults(suiteName: phoneSuite))
        phoneDefaults.removePersistentDomain(forName: phoneSuite)
    }

    private var context: NSManagedObjectContext { stack.viewContext }
    private var phone: CDAttendanceStore { CDAttendanceStore(context: context, role: .assistant) }

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

    @Test("Closed on the roll; a phone looks after two came in late; the last absence cleared: Late on both (2)")
    func phoneLookingBetweenTheChangesAgrees() throws {
        let kids = [student("Ari"), student("Ben"), student("Cal")]
        let roll = roll(kids)
        #expect(roll.closeArrival(modelContext: context)?.records.count == 3)
        try context.save()

        // Marked Late after the close, from a phone.
        for child in kids.prefix(2) { #expect(phone.updateStatus(try record(of: child), to: .tardy)) }
        try context.save()
        #expect(try phone.arrivalClosed(on: today, defaults: phoneDefaults))

        #expect(phone.unmark(try record(of: kids[2])))
        try context.save()
        #expect(try phone.arrivalClosed(on: today, defaults: phoneDefaults), "Ari and Ben came in after the close")
        roll.load(students: kids, modelContext: context)
        #expect(roll.phase == .late)
    }

    @Test("Reopened with every closed-out child resolved: Back to Late is offered, and goes straight there (3)")
    func reopenThenBackToLate() throws {
        let maya = student("Maya"), ari = student("Ari")
        #expect(try phone.markUnmarkedAbsent(for: today, students: [maya, ari]).count == 2)
        try context.save()
        let roll = roll([maya, ari])
        #expect(roll.phase == .late)
        #expect(phone.updateStatus(try record(of: maya), to: .tardy))
        #expect(phone.updateAbsenceReason(try record(of: ari), to: .sick))
        try context.save()
        roll.load(students: [maya, ari], modelContext: context)
        #expect(roll.phase == .late)

        roll.reopenArrival()
        roll.load(students: [maya, ari], modelContext: context)
        #expect(roll.phase == .arrival, "a reopen here still wins")
        #expect(roll.offersCloseArrival(canMark: true), "the way back to Late, with nobody to mark")
        #expect(roll.goesBackToLate)

        #expect(roll.closeArrival(modelContext: context)?.records.isEmpty == true)
        #expect(roll.phase == .late)
        roll.load(students: [maya, ari], modelContext: context)
        #expect(roll.phase == .late)
        #expect(!roll.offersCloseArrival(canMark: true))
    }
}
