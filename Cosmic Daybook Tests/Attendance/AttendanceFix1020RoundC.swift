import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The notebook's side of the fix round after review (c) of the Daybook
// Assistant's 2026-10-20 front-desk fixes: an Undo of an assistant's Close
// Arrival followed by a child marked present, seen in one import, reads as
// arrival again, so the guide's ParentLocker backstop doesn't send during
// arrival (2); and the roll's Send Now gate for another day, which no test
// covered (#17).
@Suite("Attendance fixes 2026-10-20: review (c) round")
@MainActor
struct AttendanceFix1020RoundC {

    private let stack: CoreDataStack
    private let defaults: UserDefaults
    private let today = AppCalendar.startOfDay(Date())

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        let suite = "AttendanceFix1020RoundC.\(UUID().uuidString)"
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

    @Test("Closed on a phone, then its Undo and Maya marked present, seen at once: arrival again here (2)")
    func undoThenPresentIsArrival() throws {
        let maya = student("Maya"), ari = student("Ari")
        let phone = CDAttendanceStore(context: context, role: .assistant)
        let closed = try phone.markUnmarkedAbsent(for: today, students: [maya, ari])
        #expect(closed.count == 2)
        try context.save()
        let mac = CDAttendanceStore(context: context)
        #expect(try mac.arrivalClosed(on: today, defaults: defaults))

        for record in closed { #expect(phone.undoAutomaticAbsence(record)) }
        let mayaRecord = try #require(closed.first { $0.studentID == maya.id?.uuidString })
        #expect(phone.updateStatus(mayaRecord, to: .present))
        try context.save()
        #expect(try !mac.arrivalClosed(on: today, defaults: defaults))
        let roll = AttendanceViewModel(selectedDate: today, defaults: defaults)
        roll.load(students: [maya, ari], modelContext: context)
        #expect(roll.phase == .arrival)
    }

    // MARK: - #17: Send Now's question on the roll

    @Test("Send Now asks first for another day when signed in, naming the unmarked; today only for the unmarked (#17)")
    func sendNowGate() throws {
        let monday = try CoreDataTestHelpers.day("2026-10-12")
        typealias Question = ParentLockerSendQuestion

        let other = try #require(Question.beforeSendNow(on: monday, isToday: false, needsSignIn: false) { [] })
        #expect(other == .otherDay(monday, unmarked: []))
        #expect(other.day == monday, "her yes sends the day asked about")
        #expect(Question.beforeSendNow(on: monday, isToday: false, needsSignIn: false) { ["Maya S"] }
            == .otherDay(monday, unmarked: ["Maya S"]))

        #expect(Question.beforeSendNow(on: monday, isToday: true, needsSignIn: false) { [] } == nil,
                "today with everyone marked: it sends")
        #expect(Question.beforeSendNow(on: monday, isToday: true, needsSignIn: false) { ["Maya S"] }
            == .beforeSending(on: monday, unmarked: ["Maya S"]))
        #expect(Question.beforeSendNow(on: monday, isToday: false, needsSignIn: true) { [] } == nil,
                "not signed in: the sign-in opens instead, and nothing goes until it's done")
    }
}
