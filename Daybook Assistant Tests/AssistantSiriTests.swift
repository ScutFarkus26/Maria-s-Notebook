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

    private typealias Late = AssistantLatePhase

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

        #expect(try await siri.undoLast() == "closing arrival")
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
        #expect(try await siri.undoLast() == "closing arrival")
        #expect(!Late.isLate(on: monday))
        #expect(try siri.status(of: #require(kids["Noah"])) == .present)
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
