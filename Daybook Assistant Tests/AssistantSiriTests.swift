import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The Assistant's Siri commands, run on an in-memory stack through
// `AssistantSiriCommands` and `SiriAttendance(stack:role:today:)`. Serialized,
// and on days in 2031: the Late memory and Siri's undo memory are the
// standard-defaults keys the app itself reads, cleared after each test.
@Suite("Assistant Siri", .serialized)
@MainActor
struct AssistantSiriTests {

    private typealias Late = AttendanceLatePhase

    private let stack: CoreDataStack
    private let monday: Date

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        monday = try AssistantTestSupport.day("2031-01-06")
        SiriAttendanceChange.forget()
        Late.setLate(false, on: monday)
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    private func session(on day: Date? = nil) -> SiriAttendance {
        SiriAttendance(stack: stack, role: .assistant, today: (day ?? monday).addingTimeInterval(9 * 3_600))
    }

    /// Ari, Maya and Noah on the roll; Noa typed in with a later start date.
    @discardableResult
    private func classOfThree() throws -> [String: CDStudent] {
        var students: [String: CDStudent] = [:]
        for (first, last) in [("Ari", "Cedar"), ("Maya", "Stone"), ("Noah", "Linden"), ("Noa", "Winter")] {
            students[first] = AssistantTestSupport.student(first, last, in: context)
        }
        students["Noa"]?.dateStarted = try AssistantTestSupport.day("2031-02-03")
        _ = context.safeSave()
        return students
    }

    private func cleanUp() {
        SiriAttendanceChange.forget()
        Late.setLate(false, on: monday)
    }

    @Test("Close arrival marks the unmarked on the roll, closes arrival, and Undo reopens it")
    func closeAndUndo() async throws {
        defer { cleanUp() }
        let kids = try classOfThree()
        let siri = session()
        try await siri.mark(try #require(kids["Ari"]), as: .present)

        #expect(try AssistantSiriCommands.checkClose(siri) == .ready(waiting: 2))
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 2)
        #expect(Late.isLate(on: monday))
        #expect(try siri.status(of: #require(kids["Maya"])) == .absent)
        #expect(try siri.status(of: #require(kids["Noa"])) == .unmarked)
        #expect(SiriAttendanceChange.last()?.closedArrival == true)
        #expect(try AssistantSiriCommands.checkClose(siri) == .alreadyClosed)

        #expect(try await siri.undoLast() == "Done. Arrival is open again.")
        #expect(!Late.isLate(on: monday))
        #expect(try siri.status(of: #require(kids["Maya"])) == .unmarked)
        #expect(try siri.status(of: #require(kids["Ari"])) == .present)
    }

    @Test("After arrival closes, here marks tardy but never downgrades a child already present")
    func hereAfterClose() async throws {
        defer { cleanUp() }
        let kids = try classOfThree()
        let siri = session()
        let ari = try #require(kids["Ari"]), maya = try #require(kids["Maya"])
        try await siri.mark(ari, as: .present)
        _ = try await AssistantSiriCommands.closeArrival(siri)

        let late = try await siri.markHere(maya)
        #expect(late.previous == .absent && late.now == .tardy)
        let stays = try await siri.markHere(ari)
        #expect(stays.previous == .present && stays.now == .present)
    }

    // Bug hunt 2026-10-03, A1: only this phone's own Close Arrival counted,
    // so after the guide closed arrival on the Mac "here" marked present.
    @Test("Once the guide has closed arrival, here marks tardy and there's nothing left to close")
    func hereAfterGuideCloses() async throws {
        defer { cleanUp() }
        let kids = try classOfThree()
        let maya = try #require(kids["Maya"]), ari = try #require(kids["Ari"])
        let guide = CDAttendanceStore(context: context, role: .leadGuide)
        #expect(try guide.markUnmarkedAbsent(for: monday, students: [maya, ari]).count == 2)
        #expect(context.safeSave())

        let siri = session()
        #expect(try AssistantSiriCommands.checkClose(siri) == .alreadyClosed)
        #expect(try await siri.markHere(maya) == (.absent, .tardy))
    }

    @Test("Close arrival refuses a locked day and has nothing to close on a day off")
    func lockedAndDayOff() throws {
        defer { cleanUp() }
        try classOfThree()
        let saturday = try AssistantTestSupport.day("2031-01-04")
        #expect(try AssistantSiriCommands.checkClose(session(on: saturday)) == .notSchoolDay)
        #expect(try AssistantSiriCommands.missingNames(session(on: saturday)) == nil)

        #expect(AttendanceDayLocks.setLocked(true, for: monday, role: .leadGuide, in: context))
        #expect(throws: SiriAttendanceError.self) { try AssistantSiriCommands.checkClose(session()) }
    }

    @Test("Who's missing names the unmarked on the roll as the tiles do")
    func missingNames() async throws {
        defer { cleanUp() }
        let kids = try classOfThree()
        AssistantTestSupport.student("Etty", "Goldman", in: context)
        AssistantTestSupport.student("Etty", "Rosen", in: context)
        _ = context.safeSave()
        let siri = session()
        try await siri.mark(try #require(kids["Maya"]), as: .present)

        #expect(try AssistantSiriCommands.missingNames(siri) == ["Ari", "Etty G", "Etty R", "Noah"])
        #expect(siri.spokenName(for: try #require(kids["Maya"])) == "Maya")
    }

    @Test("Undoing a Close Arrival that found everyone marked reopens arrival, once")
    func undoEmptyClose() async throws {
        defer { cleanUp() }
        let kids = try classOfThree()
        let siri = session()
        for name in ["Ari", "Maya", "Noah"] { try await siri.mark(try #require(kids[name]), as: .present) }

        #expect(try await AssistantSiriCommands.closeArrival(siri) == 0)
        #expect(Late.isLate(on: monday))
        #expect(try await siri.undoLast() == "Done. Arrival is open again.")
        #expect(!Late.isLate(on: monday))
        #expect(try siri.status(of: #require(kids["Noah"])) == .present)
    }

    // MARK: - Undo and Close Arrival edge cases (logic-break sweep 2026-09-29, F12)

    @Test("Undo puts back a reason-only change, down to Close Arrival's automatic absence")
    func undoReasonOnly() async throws {
        defer { cleanUp() }
        let kids = try classOfThree()
        let siri = session()
        let maya = try #require(kids["Maya"])
        _ = try await AssistantSiriCommands.closeArrival(siri)
        let records = try siri.store.loadRecords(for: siri.today)
        let record = try #require(records.first { $0.studentID == maya.id?.uuidString })
        #expect(AttendanceDeduplication.isAutomaticAbsence(record))

        try await siri.mark(maya, as: .absent, reason: .sick)
        #expect(record.absenceReason == .sick)
        #expect(try await siri.undoLast() == "Done. Maya's absence reason is back the way it was.")
        #expect(record.status == .absent)
        #expect(AttendanceDeduplication.isAutomaticAbsence(record))
        #expect(!context.hasChanges)
    }

    @Test("Undo on a locked day refuses and keeps the change for when it's unlocked")
    func undoLockedDay() async throws {
        defer { cleanUp() }
        let kids = try classOfThree()
        let siri = session()
        let ari = try #require(kids["Ari"])
        try await siri.mark(ari, as: .present)
        #expect(AttendanceDayLocks.setLocked(true, for: monday, role: .leadGuide, in: context))

        await #expect(throws: SiriAttendanceError.self) { try await siri.undoLast() }
        #expect(SiriAttendanceChange.last() != nil)
        #expect(try siri.status(of: ari) == .present)

        #expect(AttendanceDayLocks.setLocked(false, for: monday, role: .leadGuide, in: context))
        #expect(try await siri.undoLast() == "Done. Ari isn't marked present anymore.")
        #expect(try siri.status(of: ari) == .unmarked)
    }

    @Test("A day locked while Siri waits for her yes isn't closed")
    func closeLockedAfterConfirm() async throws {
        defer { cleanUp() }
        try classOfThree()
        let siri = session()
        #expect(try AssistantSiriCommands.checkClose(siri) == .ready(waiting: 3))
        #expect(AttendanceDayLocks.setLocked(true, for: monday, role: .leadGuide, in: context))

        await #expect(throws: SiriAttendanceError.self) { try await AssistantSiriCommands.closeArrival(siri) }
        #expect(!Late.isLate(on: monday))
        #expect(SiriAttendanceChange.last() == nil)
    }

    @Test("Closing arrival on the grid retires Siri's older change, so Undo can't reach back past it")
    func gridCloseForgetsSiriUndo() async throws {
        // A past Monday: the grid closes arrival only on a day that has come.
        let past = try AssistantTestSupport.day("2021-01-04")
        defer {
            cleanUp()
            Late.setLate(false, on: past)
        }
        let kids = try classOfThree()
        let siri = session(on: past)
        try await siri.mark(try #require(kids["Ari"]), as: .present)
        #expect(SiriAttendanceChange.last() != nil)

        let grid = AssistantTestSupport.viewModel(stack, on: past, defaults: .standard)
        #expect(grid.beginLate() == 2)
        #expect(SiriAttendanceChange.last() == nil)
        await #expect(throws: SiriAttendanceError.self) { try await siri.undoLast() }
        #expect(try siri.status(of: #require(kids["Ari"])) == .present)
    }

    // MARK: - Membership

    @Test("Only an assistant row counts: a lead guide's row on the same account is not a class")
    func membershipFilter() throws {
        func row(_ role: CDClassroomMembership.ClassroomRole, zone: String) {
            let row = CDClassroomMembership(context: context)
            row.id = UUID()
            row.role = role
            row.classroomZoneID = zone
            row.ownerIdentity = "owner"
            row.joinedAt = Date()
            row.modifiedAt = Date()
        }
        row(.leadGuide, zone: "guide")
        _ = context.safeSave()
        #expect(CDClassroomMembership.current(in: context) == nil)
        #expect(CDClassroomMembership.pinnedZoneName(in: context) == nil)
        #expect(throws: SiriAttendanceError.self) { try SiriHost.checkReady(in: context) }

        row(.assistant, zone: "class")
        _ = context.safeSave()
        #expect(CDClassroomMembership.pinnedZoneName(in: context) == "class")
        #expect(CDClassroomMembership.currentRole(in: context) == .assistant)
        try SiriHost.checkReady(in: context)
    }
}
