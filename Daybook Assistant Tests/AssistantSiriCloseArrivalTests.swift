import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Close Arrival by Siri, its Undo, and the class's calendar: the Siri
// findings of the 2026-10-04 bug hunt. In `AssistantSiriTests`, so they run
// one at a time with it: the Late memory and Siri's undo memory are the
// app's own standard-defaults keys. Each test makes its own stack, on the
// suite's Monday in 2031 (its `init` and these tests' clean-up clear it).
extension AssistantSiriTests {

    private static let siriMonday = "2031-01-06"

    private static func forgetSiriState(on day: Date) {
        SiriAttendanceChange.forget()
        AttendanceLatePhase.setLate(false, on: day)
    }

    /// Ari and Maya on the roll, saved.
    private static func twoChildren(in context: NSManagedObjectContext) -> (ari: CDStudent, maya: CDStudent) {
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        _ = context.safeSave()
        return (ari, maya)
    }

    private static func siri(_ stack: CoreDataStack, on day: Date) -> SiriAttendance {
        SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
    }

    // Step 2: Siri's Undo reopened arrival on purpose, so after the guide
    // closed it, "here" still marked present on this phone.
    @Test("After Siri undoes Close Arrival, the guide closing arrival makes here mark late")
    func siriUndoFollowsTheRecords() async throws {
        let day = try AssistantTestSupport.day(Self.siriMonday)
        defer { Self.forgetSiriState(on: day) }
        let stack = try AssistantTestSupport.makeStack()
        let (ari, maya) = Self.twoChildren(in: stack.viewContext)
        let siri = Self.siri(stack, on: day)
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 2)
        #expect(try await siri.undoLast() == "Done. Arrival is open again.")
        #expect(SiriHost.statusForHere(on: day, store: siri.store) == .present)

        let guide = CDAttendanceStore(context: stack.viewContext, role: .leadGuide)
        #expect(try guide.markUnmarkedAbsent(for: day, students: [ari, maya]).count == 2)
        #expect(stack.viewContext.safeSave())
        #expect(SiriHost.statusForHere(on: day, store: siri.store) == .tardy)
        #expect(try AssistantSiriCommands.checkClose(siri) == .alreadyClosed)
    }

    // Step 1: another device's Close Arrival on the same child (before they
    // synced) kept her absent, and the day closed, after Siri's Undo.
    @Test("Siri's Undo of Close Arrival clears another device's automatic absence, and a plain absent stays plain")
    func siriUndoClearsAutomaticCopies() async throws {
        let day = try AssistantTestSupport.day(Self.siriMonday)
        defer { Self.forgetSiriState(on: day) }
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let (_, maya) = Self.twoChildren(in: context)
        let siri = Self.siri(stack, on: day)
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 2)
        let copy = CDAttendanceRecord(context: context)
        copy.studentID = try #require(maya.id?.uuidString)
        copy.date = day
        copy.status = .absent
        copy.absenceReasonRaw = AttendanceDeduplication.automaticAbsenceRaw
        copy.recordedBy = CDClassroomMembership.ClassroomRole.leadGuide.rawValue
        copy.modifiedAt = Date().addingTimeInterval(-60)
        #expect(context.safeSave())

        #expect(try await siri.undoLast() == "Done. Arrival is open again.")
        #expect(try siri.status(of: maya) == .unmarked)
        #expect(try !siri.store.arrivalClosed(on: day))

        // "Maya is absent": a person's absence, not a closed arrival.
        try await siri.mark(maya, as: .absent)
        #expect(try !siri.store.arrivalClosed(on: day))
        #expect(SiriHost.statusForHere(on: day, store: siri.store) == .present)
    }

    // Step 13: arrival closed on the grid while Siri waited for her yes;
    // Siri closed it again and remembered it as its own, so "Undo that" took
    // back the grid's Close Arrival.
    @Test("Siri's Close Arrival, confirmed after arrival closed on the grid, says so and changes nothing")
    func closeRacingTheGrid() async throws {
        let day = try AssistantTestSupport.day(Self.siriMonday)
        defer { Self.forgetSiriState(on: day) }
        let stack = try AssistantTestSupport.makeStack()
        let (ari, maya) = Self.twoChildren(in: stack.viewContext)
        let siri = Self.siri(stack, on: day)
        #expect(try AssistantSiriCommands.checkClose(siri) == .ready(waiting: 2))

        // The grid closes arrival while Siri asks.
        let grid = CDAttendanceStore(context: stack.viewContext, role: .assistant)
        #expect(try grid.markUnmarkedAbsent(for: day, students: [ari, maya]).count == 2)
        #expect(stack.viewContext.safeSave())
        AttendanceLatePhase.setLate(true, on: day)

        let error = await #expect(throws: SiriAttendanceError.self) {
            try await AssistantSiriCommands.closeArrival(siri)
        }
        #expect(error.map { String(describing: $0) } == "arrivalAlreadyClosed")
        #expect(SiriAttendanceChange.last() == nil)
        #expect(AttendanceLatePhase.isLate(on: day))
    }

    // Step 15: Siri read days off from both stores, so one from a notebook of
    // her own on the same Apple Account made a school day read as a day off.
    @Test("Siri goes by the class's own calendar, not a day off in the private store")
    func schoolDayFromTheShareOnly() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let coordinator = try #require(context.persistentStoreCoordinator)
        // The phone's shape: the class's shared store beside the first one.
        let shared = try coordinator.addPersistentStore(
            type: .inMemory,
            configuration: CoreDataStack.sharedConfiguration,
            at: URL(fileURLWithPath: "/dev/null/shared")
        )
        let monday = try AssistantTestSupport.day(Self.siriMonday)
        let tuesday = try AssistantTestSupport.day("2031-01-07")
        let ownDayOff = CDNonSchoolDay(context: context)
        ownDayOff.date = monday
        let classDayOff = CDNonSchoolDay(context: context)
        classDayOff.date = tuesday
        context.assign(classDayOff, to: shared)
        #expect(context.safeSave())
        #expect(ownDayOff.objectID.persistentStore != shared)

        #expect(Self.siri(stack, on: monday).isSchoolDay)
        #expect(!Self.siri(stack, on: tuesday).isSchoolDay)
    }
}
