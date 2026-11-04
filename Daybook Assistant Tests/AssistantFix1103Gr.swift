import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Daybook Assistant bugs and efficiency hunt 2026-11-03, the grid's findings
// (#3, #4, #5, #6, #22, #23, #24): the ‹ › arrows and the welcome back read
// her own notebook's calendar and marks, an id-less child's tile changed id
// on every load, and an import's reload still ran after she left the tab.
@Suite("Assistant grid (Fix1103 Gr)")
@MainActor
struct AssistantFix1103GrTests {

    // MARK: - #5 The arrows and the welcome back read the classroom share only

    /// Private and shared SQLite stores in a temporary folder, as on a phone.
    private func splitContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            _ = try coordinator.addPersistentStore(
                type: .sqlite, configuration: configuration,
                at: dir.appendingPathComponent("\(configuration).sqlite")
            )
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func store(_ configuration: String, in context: NSManagedObjectContext) throws -> NSPersistentStore {
        let stores = context.persistentStoreCoordinator?.persistentStores ?? []
        return try #require(stores.first { $0.configurationName == configuration })
    }

    private func grid(_ context: NSManagedObjectContext, on day: Date) -> AssistantAttendanceViewModel {
        let model = AssistantAttendanceViewModel(
            context: context, container: nil, date: day, defaults: AssistantTestSupport.makeDefaults(),
            now: { day.addingTimeInterval(9 * 3_600) }
        )
        model.load()
        return model
    }

    private func day(_ iso: String) throws -> Date { try AssistantTestSupport.day(iso) }

    @Test("The arrows don't skip a class day her own notebook has off, or stop on its school Saturday")
    func arrowsFollowTheClassCalendar() throws {
        let context = try splitContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        let mine = try store(CoreDataStack.privateConfiguration, in: context)
        context.assign(AssistantTestSupport.student("Ari", "Cedar", in: context), to: shared)
        // Her own notebook: Tuesday off, and Saturday a school day.
        let holiday = CDNonSchoolDay(context: context)
        holiday.date = try day("2031-01-07")
        context.assign(holiday, to: mine)
        let saturday = CDSchoolDayOverride(context: context)
        saturday.date = try day("2031-01-11")
        context.assign(saturday, to: mine)
        #expect(context.safeSave())

        let model = grid(context, on: try day("2031-01-06"))
        model.step(forward: true)
        #expect(model.date == (try day("2031-01-07")))

        let friday = grid(context, on: try day("2031-01-10"))
        friday.step(forward: true)
        #expect(friday.date == (try day("2031-01-13")))
        friday.step(forward: false)
        #expect(friday.date == (try day("2031-01-10")))
    }

    @Test("The class's own days off are still skipped")
    func arrowsSkipTheClassDaysOff() throws {
        let context = try splitContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        context.assign(AssistantTestSupport.student("Ari", "Cedar", in: context), to: shared)
        let holiday = CDNonSchoolDay(context: context)
        holiday.date = try day("2031-01-07")
        context.assign(holiday, to: shared)
        let saturday = CDSchoolDayOverride(context: context)
        saturday.date = try day("2031-01-11")
        context.assign(saturday, to: shared)
        #expect(context.safeSave())

        let model = grid(context, on: try day("2031-01-06"))
        model.step(forward: true)
        #expect(model.date == (try day("2031-01-08")))
        let friday = grid(context, on: try day("2031-01-10"))
        friday.step(forward: true)
        #expect(friday.date == (try day("2031-01-11")))
    }

    /// A mark in `store` for `student` on each of `isos`.
    private func mark(
        _ student: CDStudent, _ status: AttendanceStatus, on isos: [String],
        in store: NSPersistentStore, context: NSManagedObjectContext
    ) throws {
        for iso in isos {
            let record = CDAttendanceRecord(context: context)
            record.studentID = try #require(student.id?.uuidString)
            record.date = try day(iso)
            record.status = status
            context.assign(record, to: store)
        }
    }

    @Test("Her own notebook's marks don't make a child back after days away")
    func welcomeBackIgnoresHerOwnMarks() throws {
        let context = try splitContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        let mine = try store(CoreDataStack.privateConfiguration, in: context)
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        context.assign(maya, to: shared)
        try mark(maya, .absent, on: ["2031-01-10"], in: shared, context: context)
        try mark(maya, .absent, on: ["2031-01-08", "2031-01-09"], in: mine, context: context)
        #expect(context.safeSave())

        #expect(AttendanceWelcomeBack.returning(on: try day("2031-01-13"), in: context).isEmpty)
        #expect(grid(context, on: try day("2031-01-13")).rows.first?.daysAway == nil)
    }

    @Test("Her own notebook's days off don't make a child back after days away")
    func welcomeBackIgnoresHerOwnDaysOff() throws {
        let context = try splitContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        let mine = try store(CoreDataStack.privateConfiguration, in: context)
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        context.assign(maya, to: shared)
        // Away Tuesday, Wednesday and Friday; here Thursday, which her own notebook has off.
        try mark(maya, .absent, on: ["2031-01-07", "2031-01-08", "2031-01-10"], in: shared, context: context)
        try mark(maya, .present, on: ["2031-01-09"], in: shared, context: context)
        let holiday = CDNonSchoolDay(context: context)
        holiday.date = try day("2031-01-09")
        context.assign(holiday, to: mine)
        #expect(context.safeSave())

        #expect(AttendanceWelcomeBack.returning(on: try day("2031-01-13"), in: context).isEmpty)
    }

    @Test("The class's own marks still welcome a child back")
    func welcomeBackFromTheClass() throws {
        let context = try splitContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        context.assign(maya, to: shared)
        try mark(maya, .absent, on: ["2031-01-08", "2031-01-09", "2031-01-10"], in: shared, context: context)
        #expect(context.safeSave())

        let id = try #require(maya.id?.uuidString)
        #expect(AttendanceWelcomeBack.returning(on: try day("2031-01-13"), in: context) == [id: 3])
    }

    // MARK: - #24 A child with no id keeps one tile

    @Test("A child with no id keeps the same row id from load to load")
    func idlessRowKeepsItsID() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let nameless = AssistantTestSupport.student("Ari", "Cedar", in: context)
        nameless.id = nil
        let other = AssistantTestSupport.student("Maya", "Stone", in: context)
        other.id = nil
        #expect(context.safeSave())
        let monday = try day("2031-01-06")

        let first = AttendanceRow(student: nameless, record: nil, shortName: "Ari", day: monday)
        let again = AttendanceRow(student: nameless, record: nil, shortName: "Ari", day: monday)
        let maya = AttendanceRow(student: other, record: nil, shortName: "Maya", day: monday)
        #expect(first.id == again.id)
        #expect(first == again)
        #expect(first.id != maya.id)
    }

}

// The grid's loads: an import's reload after she left the tab (#24), a screen
// started in the background (#22), the reminder, Control Center and Siri
// loads (#6), the lock read once (#23), and an Undo a lock refused (#24).
@Suite("Assistant grid loads (Fix1103 Gr)")
@MainActor
struct AssistantFix1103GrLoadTests {

    // MARK: - #24 Leaving the tab drops an import's reload still settling

    @Test("An import's reload still settling when she leaves the tab doesn't run")
    func settlingReloadEndsWithTheTab() async throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari"])
        let model = fixture.model()
        let following = Task { await model.followRemoteImports(into: "store") }
        await Task.yield()
        let loads = model.loadGeneration
        model.importReloader?.importFinished()
        following.cancel()
        await following.value
        try await Task.sleep(for: .milliseconds(1_500))
        #expect(model.loadGeneration == loads)
    }

    @Test("On the tab, an import still reloads the day once it settles")
    func settlingReloadRunsOnTheTab() async throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari"])
        let model = fixture.model()
        let following = Task { await model.followRemoteImports(into: "store", isInBackground: false) }
        await Task.yield()
        let loads = model.loadGeneration
        model.importReloader?.importFinished()
        try await Task.sleep(for: .milliseconds(1_500))
        #expect(model.loadGeneration == loads + 1)
        following.cancel()
        await following.value
    }

    // MARK: - #22 A screen first shown in the background starts away

    @Test("A screen first shown with the app in the background holds imports for the return")
    func startsAwayInTheBackground() async throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari"])
        let model = fixture.model()
        let away = Task { await model.followRemoteImports(into: "store", isInBackground: true) }
        await Task.yield()
        #expect(model.importReloader?.isAway == true)
        away.cancel()
        await away.value

        let inFront = Task { await model.followRemoteImports(into: "store", isInBackground: false) }
        await Task.yield()
        #expect(model.importReloader?.isAway == false)
        inFront.cancel()
        await inFront.value
    }

    // MARK: - #6 One load per trip back, and none for nothing new

    @Test("A tapped reminder doesn't load today again when it's already on screen")
    func showTodayOnToday() throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari"])
        let model = fixture.model()
        let loads = model.loadGeneration
        model.showToday()
        #expect(model.loadGeneration == loads)

        // Away, it loads: the tap may come before the return.
        model.followScene(isActive: false)
        model.showToday()
        #expect(model.loadGeneration == loads + 1)
    }

    @Test("A tapped reminder still brings today back from another day")
    func showTodayFromAnotherDay() throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari"])
        let clock = AssistantGridFixture.Clock(fixture.monday.addingTimeInterval(9 * 3_600))
        let friday = try AssistantTestSupport.day("2031-01-03")
        let model = fixture.model(on: friday, clock: clock)
        model.showToday()
        #expect(model.date == fixture.monday)
    }

    @Test("Back from Control Center with nothing new, the day doesn't load again")
    func inactiveFlipWithNothingNew() throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari"])
        let model = fixture.model()
        let loads = model.loadGeneration
        model.followScene(isActive: false)
        model.returnedToApp(fromBackground: false)
        #expect(model.loadGeneration == loads)

        // Back from the background, it loads as always.
        model.followScene(isActive: false)
        model.returnedToApp(fromBackground: true)
        #expect(model.loadGeneration == loads + 1)
    }

    @Test("Back from a moment away after midnight, the grid goes to today")
    func inactiveFlipAfterTheDayTurned() throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari"])
        let clock = AssistantGridFixture.Clock(fixture.monday.addingTimeInterval(9 * 3_600))
        let model = fixture.model(clock: clock)
        model.followScene(isActive: false)
        clock.now = fixture.monday.addingTimeInterval(33 * 3_600)
        model.returnedToApp(fromBackground: false)
        #expect(model.date == (try AssistantTestSupport.day("2031-01-07")))
    }

    @Test("A Siri mark waits for the app's return while it's away, and none loads off the tab")
    func siriMarkFollowsTheScreen() async throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari"])
        let model = fixture.model()
        let following = Task { await model.followRemoteImports(into: "store", isInBackground: false) }
        await Task.yield()
        let loads = model.loadGeneration

        // On screen: at once.
        model.siriChanged()
        #expect(model.loadGeneration == loads + 1)

        // Siri over the app: held, then shown by the return, once.
        model.followScene(isActive: false)
        model.siriChanged()
        #expect(model.loadGeneration == loads + 1)
        model.returnedToApp(fromBackground: false)
        #expect(model.loadGeneration == loads + 2)

        // Another tab: nothing; the tab's return loads.
        following.cancel()
        await following.value
        model.siriChanged()
        #expect(model.loadGeneration == loads + 2)
    }

    // MARK: - #24 An Undo refused by a lock says so

    @Test("An Undo on a day locked meanwhile reports it didn't go back, so the send stays")
    func lockedUndoDoesNotGoBack() throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari", "Maya"])
        let model = fixture.model()
        #expect(model.beginLate() == 2)
        let lock = CDAttendanceDayLock(context: fixture.context)
        lock.date = fixture.monday
        #expect(fixture.context.safeSave())
        #expect(!model.returnToArrival(undo: true))
        #expect(model.phase == .late)
    }

    @Test("An Undo on an open day goes back")
    func undoGoesBack() throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari", "Maya"])
        let model = fixture.model()
        #expect(model.beginLate() == 2)
        #expect(model.returnToArrival(undo: true))
        #expect(model.phase == .arrival)
        #expect(model.unmarkedCount == 2)
    }

    // MARK: - #23 One lock read per load

    @Test("The role half of the write check, and the grid's marking on a locked day")
    func roleAndLock() throws {
        let fixture = try AssistantGridFixture()
        fixture.classOf(["Ari"])
        #expect(CDAttendanceStore(context: fixture.context, role: .assistant).roleMayWrite)
        #expect(fixture.model().canMark)
        let lock = CDAttendanceDayLock(context: fixture.context)
        lock.date = fixture.monday
        #expect(fixture.context.safeSave())
        let locked = fixture.model()
        #expect(locked.isLocked && !locked.canMark)
    }
}
