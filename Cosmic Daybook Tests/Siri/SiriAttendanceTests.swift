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
}
