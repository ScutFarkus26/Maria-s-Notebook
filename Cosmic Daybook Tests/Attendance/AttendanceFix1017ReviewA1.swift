import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-17 review (a1), #5: marking a child back after days away
// as Left Early still showed "Welcome back". Leaving early isn't coming in.
@Suite("Attendance welcome back skips Left Early (Fix1017ReviewA1)")
@MainActor
struct AttendanceFix1017ReviewA1Tests {

    private let stack: CoreDataStack
    private let defaults: UserDefaults

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        let suite = "AttendanceFix1017ReviewA1Tests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    private func student(_ first: String) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = first
        student.lastName = "Stone"
        student.dateStarted = Calendar.current.date(byAdding: .year, value: -1, to: Date())
        return student
    }

    private func mark(_ student: CDStudent, _ status: AttendanceStatus, on day: String) throws {
        let store = CDAttendanceStore(context: context)
        let record = try #require(try store.ensureRecord(for: student, on: try CoreDataTestHelpers.day(day)))
        #expect(store.updateStatus(record, to: status))
    }

    @Test("A returning child marked Left Early gets no welcome")
    func leftEarlyNoWelcome() throws {
        let maya = student("Maya")
        for day in ["2026-09-09", "2026-09-10", "2026-09-11"] { try mark(maya, .absent, on: day) }
        let roll = AttendanceViewModel(selectedDate: try CoreDataTestHelpers.day("2026-09-14"), defaults: defaults)
        roll.load(students: [maya], modelContext: context)
        let row = try #require(roll.rows.first)
        #expect(row.daysAway == 3)

        #expect(roll.setStatus(.leftEarly, for: row, modelContext: context))
        #expect(roll.welcome == nil)
    }
}
