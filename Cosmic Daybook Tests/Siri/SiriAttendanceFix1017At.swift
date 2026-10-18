import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-17, #1, #5 and #7's Siri answer. In `SiriAttendanceTests`,
// so they run one at a time with it: Siri's undo memory and the Late memory
// are the app's own standard-defaults keys. Each test makes its own stack, on
// a Tuesday the suite's other tests don't use.
extension SiriAttendanceTests {

    private static let fixDay = "2026-10-13"

    private static func fixStack() throws -> (CoreDataStack, Date) {
        (try CoreDataTestHelpers.makeInMemoryStack(), try CoreDataTestHelpers.day(fixDay))
    }

    private static func siri(_ stack: CoreDataStack, on day: Date) -> SiriAttendance {
        SiriAttendance(stack: stack, role: .leadGuide, today: day.addingTimeInterval(9 * 3_600))
    }

    private static func maya(in context: NSManagedObjectContext) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = "Maya"
        student.lastName = "Stone"
        student.enrollmentStatusRaw = CDStudent.EnrollmentStatus.enrolled.rawValue
        _ = context.safeSave()
        return student
    }

    /// `student` marked `status` on the grid when she arrived, then Left
    /// Early when she left, as the roll leaves her.
    private static func leftEarly(
        _ student: CDStudent, from status: AttendanceStatus, times: (arrived: Date, left: Date),
        in context: NSManagedObjectContext
    ) throws -> CDAttendanceRecord {
        let store = CDAttendanceStore(context: context, role: .leadGuide)
        let day = try CoreDataTestHelpers.day(fixDay)
        let record = try #require(try store.ensureRecord(for: student, on: day))
        store.updateStatus(record, to: status)
        store.updateStatus(record, to: .leftEarly)
        record.markedAt = times.arrived
        record.leftAt = times.left
        #expect(context.safeSave())
        #expect(record.statusBeforeLeavingRaw == status.rawValue)
        return record
    }

    // #1: "Mark Maya here" on a child back from the dentist re-marked her:
    // a new arrival time, the trip lost, and late once arrival had closed.
    @Test("Here on a child who left early brings her back in class, arrival and trip kept, and Undo puts her back")
    func hereOnLeftEarlyIsBackInClass() async throws {
        let (stack, day) = try Self.fixStack()
        defer { SiriAttendanceChange.forget() }
        let context = stack.viewContext
        let maya = Self.maya(in: context)
        let arrived = day.addingTimeInterval(8 * 3_600 + 2 * 60)
        let left = day.addingTimeInterval(10 * 3_600 + 15 * 60)
        let record = try Self.leftEarly(maya, from: .present, times: (arrived, left), in: context)

        let siri = Self.siri(stack, on: day)
        let result = try await siri.markHere(maya)
        #expect(result == (.leftEarly, .present))
        #expect(record.status == .present)
        #expect(record.markedAt == arrived)
        #expect(record.leftAt == left)
        #expect(record.statusBeforeLeavingRaw == nil)
        #expect(!context.hasChanges)
        #expect(SiriAttendanceChange.last()?.summary == "Maya Stone back in class")

        _ = try await siri.undoLast()
        #expect(record.status == .leftEarly)
        #expect(record.markedAt == arrived)
        #expect(record.leftAt == left)
        #expect(record.statusBeforeLeavingRaw == AttendanceStatus.present.rawValue)
    }

    @Test("After arrival has closed, a late child back from a trip is late again, not re-marked")
    func hereOnLeftEarlyKeepsLate() async throws {
        let (stack, day) = try Self.fixStack()
        let siri = Self.siri(stack, on: day)
        AttendanceLatePhase.setLate(true, on: siri.today)
        defer {
            AttendanceLatePhase.setLate(false, on: siri.today)
            SiriAttendanceChange.forget()
        }
        let context = stack.viewContext
        let maya = Self.maya(in: context)
        let arrived = day.addingTimeInterval(9 * 3_600 + 10 * 60)
        let left = day.addingTimeInterval(11 * 3_600)
        let record = try Self.leftEarly(maya, from: .tardy, times: (arrived, left), in: context)

        #expect(try await siri.markHere(maya) == (.leftEarly, .tardy))
        #expect(record.status == .tardy)
        #expect(record.markedAt == arrived)
        #expect(record.leftAt == left)
    }

    @Test("Siri says a child who left early is back in class")
    func backInClassAnswer() {
        let present = MarkHereIntent.answer(name: "Maya Stone", previous: .leftEarly, now: .present)
        #expect(present.full == "Maya Stone is back in class.")
        #expect(present.supporting == "Back in class")
        let late = MarkHereIntent.answer(name: "Maya Stone", previous: .leftEarly, now: .tardy)
        #expect(late.full == "Maya Stone is back in class.")
        // Unchanged: the other answers.
        #expect(MarkHereIntent.answer(name: "Maya Stone", previous: .unmarked, now: .present).full
            == "Maya Stone is marked present.")
        #expect(MarkHereIntent.answer(name: "Maya Stone", previous: .absent, now: .tardy).full
            == "Arrival has closed, so Maya Stone is marked late.")
    }

    // #5: a vacation marked ahead stayed on the record after she came in,
    // and came back on a later plain "absent".
    @Test("A reason goes when the mark leaves absent, and Undo brings it back")
    func reasonLeavesWithTheAbsence() async throws {
        let (stack, day) = try Self.fixStack()
        defer { SiriAttendanceChange.forget() }
        let context = stack.viewContext
        let maya = Self.maya(in: context)
        let siri = Self.siri(stack, on: day)
        try await siri.mark(maya, as: .absent, reason: .vacation)
        let record = try #require(try siri.store.loadRecords(for: day).first)
        #expect(record.absenceReason == .vacation)

        try await siri.mark(maya, as: .present)
        #expect(record.absenceReasonRaw == AbsenceReason.none.rawValue)
        _ = try await siri.undoLast()
        #expect(record.status == .absent && record.absenceReason == .vacation)

        try await siri.mark(maya, as: .present)
        try await siri.mark(maya, as: .absent)
        #expect(record.status == .absent)
        #expect(record.absenceReasonRaw == AbsenceReason.none.rawValue)
    }

    // #7: "Mark Maya absent, sick" on a child already absent and sick
    // answered as if it had changed something.
    @Test("Absent with the reason a child already has says nothing changed")
    func absentWithSameReasonAnswer() async throws {
        let unchanged = MarkAbsentIntent.answer(name: "Maya Stone", previous: .absent, reason: .sick, changed: false)
        #expect(unchanged.full == "Maya Stone is already marked absent: sick.")
        #expect(unchanged.supporting == "Already absent")
        let changed = MarkAbsentIntent.answer(name: "Maya Stone", previous: .absent, reason: .sick, changed: true)
        #expect(changed.full == "Maya Stone is marked absent: sick.")
        #expect(MarkAbsentIntent.answer(name: "Maya Stone", previous: .absent, reason: nil, changed: false).full
            == "Maya Stone was already marked absent.")
        #expect(MarkAbsentIntent.answer(name: "Maya Stone", previous: .present, reason: .sick, changed: true).full
            == "Maya Stone is marked absent.")

        let (stack, day) = try Self.fixStack()
        defer { SiriAttendanceChange.forget() }
        let maya = Self.maya(in: stack.viewContext)
        let siri = Self.siri(stack, on: day)
        #expect(try await siri.markAbsent(maya, reason: .sick) == (.unmarked, true))
        #expect(try await siri.markAbsent(maya, reason: .sick) == (.absent, false))
        #expect(try await siri.markAbsent(maya, reason: .family) == (.absent, true))
    }
}
