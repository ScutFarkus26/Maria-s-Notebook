import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The path every Siri attendance command takes: marks through
/// `CDAttendanceStore`, refuses what a grid tap would refuse, and remembers
/// the change so "Undo that" can put it back without clobbering a later mark.
/// Serialized: the undo memory is one UserDefaults key.
@Suite("Siri attendance", .serialized)
@MainActor
struct SiriAttendanceTests {

    private let stack: CoreDataStack
    private let monday: Date

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        monday = try CoreDataTestHelpers.day("2026-10-12")
        SiriAttendanceChange.forget()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    private func session() -> SiriAttendance {
        SiriAttendance(stack: stack, role: .leadGuide, today: monday.addingTimeInterval(9 * 3_600))
    }

    private func makeStudent(_ first: String, status: CDStudent.EnrollmentStatus = .enrolled) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = first
        student.lastName = "Stone"
        student.enrollmentStatusRaw = status.rawValue
        _ = context.safeSave()
        return student
    }

    private func entity(for student: CDStudent) throws -> StudentEntity {
        try #require(StudentEntity(student: student))
    }

    /// The error's case name ("dayLocked", "changedSince"), nil for any other error.
    nonisolated private static func siriError(_ error: any Error) -> String? {
        guard let error = error as? SiriAttendanceError else { return nil }
        return String(describing: error).components(separatedBy: "(").first
    }

    @Test("A mark saves through the store and is remembered for Undo")
    func markAndRemember() async throws {
        let maya = makeStudent("Maya")
        let siri = session()
        let previous = try await siri.mark(siri.student(for: entity(for: maya)), as: .present)

        #expect(previous == .unmarked)
        #expect(try siri.status(of: maya) == .present)
        #expect(!context.hasChanges)
        let change = try #require(SiriAttendanceChange.last())
        #expect(change.summary == "Maya Stone present")
        #expect(change.marks.map(\.to) == [.present])
    }

    @Test("Marking the status a child already has changes nothing")
    func alreadyMarked() async throws {
        let maya = makeStudent("Maya")
        let siri = session()
        try await siri.mark(maya, as: .tardy)
        SiriAttendanceChange.forget()

        let previous = try await siri.mark(maya, as: .tardy)
        #expect(previous == .tardy)
        #expect(SiriAttendanceChange.last() == nil)
    }

    @Test("Absent takes a reason, and a new reason on a child already absent is a change")
    func absentWithReason() async throws {
        let maya = makeStudent("Maya")
        let siri = session()
        try await siri.mark(maya, as: .absent, reason: .appointment)
        let record = try #require(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).first)
        #expect(record.absenceReason == .appointment)

        SiriAttendanceChange.forget()
        let previous = try await siri.mark(maya, as: .absent, reason: .sick)
        #expect(previous == .absent)
        #expect(record.absenceReason == .sick)
        #expect(SiriAttendanceChange.last() != nil)

        SiriAttendanceChange.forget()
        try await siri.mark(maya, as: .absent, reason: .sick)
        #expect(SiriAttendanceChange.last() == nil)
    }

    @Test("Reading a child's status creates no record")
    func statusReadsOnly() throws {
        let maya = makeStudent("Maya")
        #expect(try session().status(of: maya) == .unmarked)
        #expect(try context.count(for: CDFetchRequest(CDAttendanceRecord.self)) == 0)
    }

    @Test("Undo puts the mark back, once")
    func undo() async throws {
        let maya = makeStudent("Maya")
        let siri = session()
        try await siri.mark(maya, as: .present)

        let summary = try await siri.undoLast()
        #expect(summary == "Maya Stone present")
        #expect(try siri.status(of: maya) == .unmarked)
        await #expect { try await siri.undoLast() } throws: { Self.siriError($0) == "nothingToUndo" }
    }

    @Test("Undo leaves a mark someone has changed since")
    func undoAfterLaterChange() async throws {
        let maya = makeStudent("Maya")
        let siri = session()
        try await siri.mark(maya, as: .present)
        // A tap on the grid after Siri's mark.
        let record = try #require(try siri.store.loadRecords(for: monday).first)
        siri.store.updateStatus(record, to: .absent)
        _ = context.safeSave()

        await #expect { try await siri.undoLast() } throws: { Self.siriError($0) == "changedSince" }
        #expect(try siri.status(of: maya) == .absent)
    }

    /// `student`'s record on Monday, marked `status` on the grid at
    /// `markedAt`, then Left Early at `leftAt` when given.
    private func markedByGrid(
        _ student: CDStudent, _ status: AttendanceStatus, at markedAt: Date, leftAt: Date? = nil
    ) throws -> CDAttendanceRecord {
        let store = CDAttendanceStore(context: context, role: .leadGuide)
        let record = try #require(try store.ensureRecord(for: student, on: monday))
        store.updateStatus(record, to: status)
        if leftAt != nil { store.updateStatus(record, to: .leftEarly) }
        record.markedAt = markedAt
        record.leftAt = leftAt
        #expect(context.safeSave())
        return record
    }

    // Bug hunt 2026-10-03, A2: Undo re-marked the old status, which re-ran
    // the mark's timing rules. A late arrival who had left early came back
    // Left Early with no arrival, today's departure and nothing to return
    // to; a misheard "late" left a child "Present at" the time of the undo.
    @Test("Undo puts back a child who had left early as she was, times and all")
    func undoKeepsLeftEarlyTimes() async throws {
        let maya = makeStudent("Maya")
        let arrived = monday.addingTimeInterval(8 * 3_600 + 5 * 60)
        let left = monday.addingTimeInterval(11 * 3_600)
        let record = try markedByGrid(maya, .tardy, at: arrived, leftAt: left)
        #expect(record.statusBeforeLeavingRaw == AttendanceStatus.tardy.rawValue)

        let siri = session()
        try await siri.mark(maya, as: .absent)
        #expect(try await siri.undoLast() == "Maya Stone absent")
        #expect(record.status == .leftEarly)
        #expect(record.markedAt == arrived)
        #expect(record.leftAt == left)
        #expect(record.statusBeforeLeavingRaw == AttendanceStatus.tardy.rawValue)
    }

    @Test("Undoing a misheard late keeps the child's arrival time")
    func undoKeepsArrival() async throws {
        let maya = makeStudent("Maya")
        let arrived = monday.addingTimeInterval(8 * 3_600 + 5 * 60)
        let record = try markedByGrid(maya, .present, at: arrived)

        let siri = session()
        try await siri.mark(maya, as: .tardy)
        _ = try await siri.undoLast()
        #expect(record.status == .present)
        #expect(record.markedAt == arrived)
    }

    /// An invalid record on a far-off day: every save fails until it goes.
    private func breakSaves() throws -> CDAttendanceRecord {
        let broken = CDAttendanceRecord(context: context)
        broken.date = try CoreDataTestHelpers.day("2020-01-06")
        broken.setValue(nil, forKey: "studentID")
        return broken
    }

    @Test("A mark whose save fails is put back, not left for the next save")
    func failedSaveDiscardsTheMark() async throws {
        let maya = makeStudent("Maya")
        let siri = session()
        let broken = try breakSaves()

        await #expect { try await siri.mark(maya, as: .present) } throws: { Self.siriError($0) == "saveFailed" }
        context.delete(broken)
        context.processPendingChanges()
        #expect(context.insertedObjects.isEmpty)
        #expect(context.updatedObjects.isEmpty)
        #expect(try siri.status(of: maya) == .unmarked)
        #expect(SiriAttendanceChange.last() == nil)
    }

    @Test("An undo whose save fails keeps the change, so it can be tried again")
    func failedUndoCanBeRetried() async throws {
        let maya = makeStudent("Maya")
        let siri = session()
        try await siri.mark(maya, as: .present)
        let broken = try breakSaves()

        await #expect { try await siri.undoLast() } throws: { Self.siriError($0) == "saveFailed" }
        context.delete(broken)
        #expect(try siri.status(of: maya) == .present)

        #expect(try await siri.undoLast() == "Maya Stone present")
        #expect(try siri.status(of: maya) == .unmarked)
    }

    @Test("Undoing a Close Arrival that marked no one succeeds, once")
    func undoEmptyCloseArrival() async throws {
        let maya = makeStudent("Maya")
        let siri = session()
        try await siri.mark(maya, as: .present)
        SiriAttendanceChange(day: siri.today, marks: [], summary: "closing arrival", closedArrival: true).remember()

        #expect(try await siri.undoLast() == "closing arrival")
        // The earlier mark is not what Undo reached for.
        #expect(try siri.status(of: maya) == .present)
        await #expect { try await siri.undoLast() } throws: { Self.siriError($0) == "nothingToUndo" }
    }

    // Close Arrival on the notebook's roll closes it for Siri on this device
    // too, as the Daybook Assistant's does.
    @Test("After Close Arrival, \"here\" marks late but never downgrades a child already present")
    func hereAfterCloseArrival() async throws {
        let maya = makeStudent("Maya")
        let ari = makeStudent("Ari")
        let siri = session()
        try await siri.mark(ari, as: .present)
        AttendanceLatePhase.setLate(true, on: siri.today)
        defer { AttendanceLatePhase.setLate(false, on: siri.today) }

        #expect(try await siri.markHere(maya).now == .tardy)
        #expect(try await siri.markHere(ari).now == .present)
    }

    @Test("A locked day takes no marks")
    func lockedDay() async throws {
        let maya = makeStudent("Maya")
        #expect(AttendanceDayLocks.setLocked(true, for: monday, role: .leadGuide, in: context))
        _ = context.safeSave()

        let siri = session()
        await #expect { try await siri.mark(maya, as: .present) } throws: { Self.siriError($0) == "dayLocked" }
        #expect(try siri.status(of: maya) == .unmarked)
    }

    @Test("A former student is refused, not marked")
    func formerStudent() throws {
        let leah = makeStudent("Leah", status: .withdrawn)
        let siri = session()
        #expect { try siri.student(for: entity(for: leah)) } throws: { Self.siriError($0) == "notEnrolled" }
    }

    // Logic-break sweep 2026-09-29, F8: Siri went by `isEnrolled`, not the
    // day's roll the grid shows (`AttendanceRoster`), so it marked a child
    // who hadn't started yet and refused one leaving today who was still on
    // the grid.
    @Test("A child who hasn't started yet is refused")
    func notStartedYet() throws {
        let noa = makeStudent("Noa")
        noa.dateStarted = monday.addingTimeInterval(7 * 86_400)
        let siri = session()
        #expect { try siri.student(for: entity(for: noa)) } throws: { Self.siriError($0) == "notStarted" }
    }

    @Test("A child whose last day is today is still on the roll, and Siri can name her")
    func leavingToday() throws {
        let tali = makeStudent("Tali", status: .withdrawn)
        tali.dateWithdrawn = monday
        let siri = session()
        #expect(try siri.student(for: entity(for: tali)) === tali)
        #expect(SiriAttendance.nameable([tali], on: monday, in: context) == [tali])
        tali.dateWithdrawn = monday.addingTimeInterval(-86_400)
        #expect(SiriAttendance.nameable([tali], on: monday, in: context).isEmpty)
    }

    // Logic-break sweep 2026-09-29, F13: here was always present in the
    // notebook, so after the Assistant closed arrival the two apps marked
    // the same arrival differently; and the name fallback searched test
    // students.
    @Test("Once the Assistant has closed arrival, here marks tardy here too, never downgrading present")
    func hereAfterAssistantCloses() async throws {
        let maya = makeStudent("Maya"), ari = makeStudent("Ari"), noa = makeStudent("Noa")
        let siri = session()
        try await siri.mark(ari, as: .present)
        #expect(try await siri.markHere(noa) == (.unmarked, .present))

        let assistant = CDAttendanceStore(context: context, role: .assistant)
        #expect(try assistant.markUnmarkedAbsent(for: monday, students: [maya, ari]).count == 1)
        #expect(context.safeSave())

        #expect(try await siri.markHere(maya) == (.absent, .tardy))
        #expect(try await siri.markHere(ari) == (.present, .present))
    }

    @Test("When no one on the roll has the name, Siri looks at former students but never test students")
    func formerStudentsFallback() {
        let leah = makeStudent("Leah", status: .withdrawn)
        let test = makeStudent("Lil")
        test.lastName = "Dan D"
        _ = context.safeSave()
        let former = SiriHost.formerStudents(in: context)
        #expect(former.contains(leah))
        #expect(!former.contains(test))
    }
}
