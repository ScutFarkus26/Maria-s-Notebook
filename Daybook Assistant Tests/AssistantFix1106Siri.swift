import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The 2026-11-06 bug hunt, Phase 1 (report "Daybook Assistant bug hunt
// 2026-11-06", #1, #2, #3, #6, #11, #12, #13): Siri's Close Arrival follows
// the arrival bar's rules, a View-only phone sends nothing and says why, one
// rule says who Close Arrival marks, the Sample Class shows Siri's marks,
// and Siri looks a child up in the class's own store. The notebook's half is
// `Fix1106SiriTests`.

/// A class on a Monday of its own, so its Late days don't meet other tests'.
@MainActor
struct Fix1106Class {
    let stack: CoreDataStack
    let day: Date
    var context: NSManagedObjectContext { stack.viewContext }
    private(set) var students: [String: CDStudent] = [:]

    init(_ firsts: [String], day iso: String = "2031-03-10") throws {
        stack = try AssistantTestSupport.makeStack()
        day = try AssistantTestSupport.day(iso)
        for first in firsts {
            students[first] = AssistantTestSupport.student(first, "Cedar", in: stack.viewContext)
        }
        #expect(stack.viewContext.safeSave())
        forget()
    }

    func siri() -> SiriAttendance {
        SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
    }

    /// Marks `first` as another device would, saved.
    func mark(_ first: String, _ status: AttendanceStatus) throws {
        let store = CDAttendanceStore(context: context, role: .leadGuide)
        let student = try #require(students[first])
        let record = try #require(try store.ensureRecord(for: student, on: day))
        #expect(store.updateStatus(record, to: status))
        #expect(context.safeSave())
    }

    /// Gives `first` a status a newer build added, saved.
    func markWithNewerStatus(_ first: String) throws {
        let store = CDAttendanceStore(context: context, role: .leadGuide)
        let student = try #require(students[first])
        let record = try #require(try store.ensureRecord(for: student, on: day))
        record.statusRaw = "excusedByANewerBuild"
        #expect(context.safeSave())
    }

    var records: [CDAttendanceRecord] { context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)) }

    /// Whether the day reads as Late here, as Siri and the grid read it.
    var isLate: Bool {
        let store = CDAttendanceStore(context: context, role: .assistant)
        return AttendanceLatePhase.isLate(on: day, closedAnywhere: (try? store.arrivalClosed(on: day)) == true)
    }

    /// Siri's memories and this day's Late, cleared.
    func forget() {
        SiriAttendanceChange.forget()
        AttendanceLatePhase.setLate(false, on: day)
    }
}

// In `AssistantSiriTests`, so they run one at a time with it: they write the
// app's own Late, Siri memories and View only.
extension AssistantSiriTests {

    private static func said(_ error: (any Error)?) -> String? {
        (error as? SiriAttendanceError).map { String(localized: $0.localizedStringResource) }
    }

    /// Runs `body` with this phone View only, then puts it back.
    private static func viewOnly<T>(_ body: () async throws -> T) async rethrows -> T {
        let was = ClassroomPermissions.shareIsViewOnly
        ClassroomPermissions.shareIsViewOnly = true
        defer { ClassroomPermissions.shareIsViewOnly = was }
        return try await body()
    }

    // MARK: - #1 Close Arrival refuses what the bar never offers

    @Test("#1: on a View-only phone Siri's Close Arrival says so, marks no one and leaves arrival open")
    func fix1106ViewOnlyClose() async throws {
        let cls = try Fix1106Class(["Ari", "Maya"])
        defer { cls.forget() }
        let siri = cls.siri()
        await Self.viewOnly {
            let checked = #expect(throws: SiriAttendanceError.self) { try AssistantSiriCommands.checkClose(siri) }
            #expect(Self.said(checked) == AssistantSyncStatusView.viewOnlyMessage)
            let closed = await #expect(throws: SiriAttendanceError.self) {
                try await AssistantSiriCommands.closeArrival(siri)
            }
            #expect(Self.said(closed) == AssistantSyncStatusView.viewOnlyMessage)
        }
        #expect(!cls.isLate, "a child tapped in afterwards would be marked late")
        #expect(cls.records.isEmpty)
        #expect(SiriAttendanceChange.last() == nil)
    }

    @Test("#1: with the class not loaded yet, Siri's Close Arrival says so and leaves arrival open")
    func fix1106EmptyRollClose() async throws {
        let cls = try Fix1106Class([])
        defer { cls.forget() }
        let siri = cls.siri()
        let checked = #expect(throws: SiriAttendanceError.self) { try AssistantSiriCommands.checkClose(siri) }
        #expect(Self.said(checked) == AssistantSiriCommands.classNotLoadedMessage)
        _ = await #expect(throws: SiriAttendanceError.self) { try await AssistantSiriCommands.closeArrival(siri) }
        #expect(!cls.isLate)
        #expect(SiriAttendanceChange.last() == nil)
    }

    @Test("#1: with everyone really marked, Siri's Close Arrival still closes")
    func fix1106AllMarkedCloses() async throws {
        let cls = try Fix1106Class(["Ari"])
        defer { cls.forget() }
        try cls.mark("Ari", .present)
        let siri = cls.siri()
        #expect(try AssistantSiriCommands.checkClose(siri) == .ready(waiting: 0))
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 0)
        #expect(cls.isLate)
    }

    // MARK: - #6 Siri on a View-only phone

    @Test("#6: on a View-only phone Siri's here says the View-only message, not \"Open the app\"")
    func fix1106ViewOnlyHere() async throws {
        let cls = try Fix1106Class(["Ari"])
        defer { cls.forget() }
        let siri = cls.siri()
        let ari = try #require(cls.students["Ari"])
        await Self.viewOnly {
            let error = await #expect(throws: SiriAttendanceError.self) { try await siri.markHere(ari) }
            #expect(Self.said(error) == AssistantSyncStatusView.viewOnlyMessage)
            #expect(SiriHost.viewOnlyMessage == AssistantSyncStatusView.viewOnlyMessage)
        }
        #expect(cls.records.isEmpty)
    }

    // MARK: - #11 Siri counts as Close Arrival marks

    @Test("#11: Siri's count leaves out a child with no id and one with a newer build's status")
    func fix1106SiriCountMatchesClose() async throws {
        let cls = try Fix1106Class(["Ari", "Noid", "Newer"])
        defer { cls.forget() }
        cls.students["Noid"]?.id = nil
        #expect(cls.context.safeSave())
        try cls.markWithNewerStatus("Newer")
        let siri = cls.siri()
        #expect(try AssistantSiriCommands.checkClose(siri) == .ready(waiting: 1))
        #expect(try AssistantSiriCommands.missingNames(siri) == ["Ari"])
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 1)
        #expect(cls.records.contains { $0.statusRaw == "excusedByANewerBuild" }, "left as it was")
    }

    // MARK: - #2 No send when the close marked no one

    @Test("#2: a Siri close that marked no one sends nothing to ParentLocker; one that marked someone sends")
    func fix1106NoSendWhenNoneMarked() async throws {
        let cls = try Fix1106Class(["Ari"])
        defer { cls.forget() }
        try cls.mark("Ari", .present)
        ParentLockerTestSettings.pick(.parentLocker, in: cls.context)
        let siri = cls.siri()
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 0)

        let quiet = FakeParentLockerSender()
        #expect(await AssistantSiriCommands.sendAfterClose(siri, marked: 0, sync: quiet) == .notPicked)
        #expect(quiet.sentDays.isEmpty && quiet.closedDays.isEmpty, "the class didn't go again")
        let unsent = ParentLockerMemoryUnsentStore()
        #expect(await AssistantSiriCommands.sendAfterClose(siri, marked: 0, sync: nil, unsent: unsent) == .notPicked)
        #expect(unsent.load() == nil, "nothing owed for later either")
        #expect(AssistantSiriCommands.closedDialog(marked: 0, parentLocker: .notPicked)
            == "Arrival is closed. Everyone was already marked.")

        let sending = FakeParentLockerSender()
        #expect(await AssistantSiriCommands.sendAfterClose(siri, marked: 1, sync: sending) == .sent)
        #expect(sending.sentDays.count == 1)
    }

    // MARK: - #3 Undo after a Reopen Arrival

    @Test("#3: undoing Siri's close on a day reopened here reopens it again, as Siri says")
    func fix1106UndoReopensAgain() async throws {
        let cls = try Fix1106Class(["Ari", "Maya"])
        defer { cls.forget() }
        try cls.mark("Ari", .present)
        let siri = cls.siri()
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 1)
        // The bar's Reopen Arrival, then Siri closes again with everyone marked.
        AttendanceLatePhase.reopen(on: cls.day)
        #expect(!cls.isLate)
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 0)
        #expect(cls.isLate)

        #expect(try await siri.undoLast() == "Done. Arrival is open again.")
        #expect(!cls.isLate, "Maya's absence from the first close still stands, and arrival is open")
        #expect(AttendanceLatePhase.isReopened(on: cls.day))
    }

    @Test("#3: undoing Siri's close on a day not reopened goes by the records, as before")
    func fix1106UndoWithoutReopen() async throws {
        let cls = try Fix1106Class(["Ari", "Maya"])
        defer { cls.forget() }
        try cls.mark("Ari", .present)
        let siri = cls.siri()
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 1)
        _ = try await siri.undoLast()
        #expect(!cls.isLate)
        #expect(!AttendanceLatePhase.isReopened(on: cls.day))
    }

    // MARK: - #6 The front desk on a View-only phone

    @Test("#6: a View-only phone offers neither the front-desk email nor ParentLocker's sends")
    func fix1106ViewOnlyFrontDesk() async throws {
        for method in [AttendanceSendMethod.email, .parentLocker] {
            let cls = try Fix1106Class(["Ari", "Maya"])
            try cls.mark("Ari", .present)
            try cls.mark("Maya", .present)
            ParentLockerTestSettings.pick(method, in: cls.context)
            let now = cls.day.addingTimeInterval(9 * 3_600)
            let canChange = AssistantTestSupport.viewModel(cls.stack, on: cls.day, now: now)
            let offered = method == .email
                ? canChange.frontDesk.isOffered(by: canChange)
                : canChange.frontDesk.offersParentLockerSend(by: canChange)
            #expect(offered, "can make changes: offered (\(method))")

            let viewOnly = await Self.viewOnly { AssistantTestSupport.viewModel(cls.stack, on: cls.day, now: now) }
            #expect(!viewOnly.roleMayWrite)
            #expect(!viewOnly.frontDesk.isOffered(by: viewOnly))
            #expect(!viewOnly.frontDesk.offersParentLocker(by: viewOnly))
            #expect(!viewOnly.frontDesk.offersParentLockerSend(by: viewOnly))
            #expect(AssistantFrontDeskMail.reminderAction(for: viewOnly) == .nothing)
        }
    }

    // MARK: - #13 Siri's lookup reads the class's store

    @Test("#13: Siri marks the class's copy of a child who also has a row in the private store")
    func fix1106LookupReadsTheShare() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let coordinator = try #require(context.persistentStoreCoordinator)
        let own = try #require(coordinator.persistentStores.first)
        let shared = try coordinator.addPersistentStore(
            type: .inMemory,
            configuration: CoreDataStack.sharedConfiguration,
            at: URL(fileURLWithPath: "/dev/null/shared-\(UUID().uuidString)")
        )
        let day = try AssistantTestSupport.day("2031-03-10")
        let id = UUID()
        // Her own notebook's copy, with dates that don't fit today.
        let mine = AssistantTestSupport.student("Maya", "Stone", in: context)
        mine.id = id
        mine.dateStarted = try AssistantTestSupport.day("2031-09-01")
        context.assign(mine, to: own)
        let classroom = AssistantTestSupport.student("Maya", "Stone", in: context)
        classroom.id = id
        context.assign(classroom, to: shared)
        #expect(context.safeSave())

        let siri = SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
        let entity = try #require(StudentEntity(student: classroom))
        let found = try siri.student(for: entity)
        #expect(found.objectID == classroom.objectID)
        #expect(found.objectID.persistentStore === shared)
    }
}

/// The grid's half of #11 and #12: no Siri or app-wide memories, so these
/// run beside the rest.
@Suite("Assistant fixes 2026-11-06: the grid")
@MainActor
struct AssistantFix1106Grid {

    // MARK: - #11 One rule for who Close Arrival marks

    @Test("#11: a child with a newer build's status isn't counted unmarked, and the email follows the close")
    func newerStatusDoesNotBlockTheEmail() throws {
        let fixture = try AssistantGridFixture()
        let students = fixture.classOf(["Ari", "Noa"])
        let guide = fixture.guide
        let record = try #require(try guide.ensureRecord(for: students[1], on: fixture.monday))
        record.statusRaw = "excusedByANewerBuild"
        #expect(fixture.context.safeSave())

        let model = fixture.model()
        #expect(model.unmarkedCount == 1)
        #expect(model.unmarkedNames.count == 1)
        #expect(try fixture.row("Noa", in: model).status == .unmarked, "her tile shows as it did")
        #expect(model.beginLate() == 1)
        #expect(model.emailCanFollowClose())
        #expect(model.errorMessage == nil)
    }

    @Test("#11: a child marked on another device just before the close doesn't stop the email")
    func markedElsewhereDoesNotBlockTheEmail() throws {
        let fixture = try AssistantGridFixture()
        let students = fixture.classOf(["Ari", "Maya"])
        let model = fixture.model()
        #expect(model.unmarkedCount == 2)
        // Another device's mark, in before her yes but not yet on the grid.
        let guide = fixture.guide
        let record = try #require(try guide.ensureRecord(for: students[0], on: fixture.monday))
        #expect(guide.updateStatus(record, to: .present))
        #expect(fixture.context.safeSave())

        #expect(model.beginLate() == 1)
        #expect(model.emailCanFollowClose())
        #expect(model.errorMessage == nil)
        #expect(try fixture.row("Ari", in: model).status == .present, "the tile caught up")
    }

    @Test("#11: a close that left someone unmarked still keeps the email back")
    func unmarkedStillBlocksTheEmail() throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari"])
        let model = fixture.model()
        #expect(!model.emailCanFollowClose(), "arrival is still open")
        #expect(model.errorMessage != nil)
    }

    // MARK: - #12 The Sample Class shows Siri's marks

    @Test("#12: in the Sample Class a Siri mark loads the open grid")
    func sampleClassShowsSiriMarks() throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari"])
        let sample = AssistantAttendanceViewModel(
            context: fixture.context, container: nil, date: fixture.monday,
            defaults: AssistantTestSupport.makeDefaults(), isSampleClass: true,
            now: { fixture.monday.addingTimeInterval(9 * 3_600) }
        )
        sample.load()
        let loads = sample.loadGeneration
        sample.siriChanged()
        #expect(sample.loadGeneration == loads + 1)

        // The real class, with no import listener running (another tab): nothing, as before.
        let real = fixture.model()
        let realLoads = real.loadGeneration
        real.siriChanged()
        #expect(real.loadGeneration == realLoads)
    }
}
