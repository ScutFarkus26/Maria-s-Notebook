import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// Daybook Assistant bug hunt 2026-10-20, #3, #4 and #6: a stray tap on
// "Absent, Sick" lost the reason (and a second tap cleared the mark), Mark N
// Absent & Email opened after a close that failed, and the smaller ones: a
// VoiceOver tap that did nothing took the Undo away, going back to Late with
// nobody unmarked queued a ParentLocker send, the First Day header waited for
// a reload, VoiceOver said "tardy", and the private store's days off, locks
// and records reached the grid.
@Suite("Assistant grid: taps and the close (Fix1020 Gr)")
@MainActor
struct AssistantGridTapsFix1020GrTests {

    private let fixture: AssistantGridFixture
    private var monday: Date { fixture.monday }
    private var context: NSManagedObjectContext { fixture.context }
    private var guide: CDAttendanceStore { fixture.guide }

    init() throws {
        fixture = try AssistantGridFixture()
    }

    private func row(_ first: String, in model: AssistantAttendanceViewModel) throws -> AssistantGridFixture.Model.Row {
        try fixture.row(first, in: model)
    }

    // MARK: - #3 A stray tap is taken back exactly

    @Test("A stray tap on Absent, Sick is taken back by a second tap, reason and all")
    func strayTapComesBack() throws {
        let kids = fixture.classOf(["Ari", "Maya"])
        let phone = fixture.model()
        phone.markAbsent(reason: .sick, for: try row("Ari", in: phone))

        phone.tap(try row("Ari", in: phone))
        #expect(try row("Ari", in: phone).status == .present)
        #expect(phone.statusAfterTap(for: try row("Ari", in: phone)) == .absent)

        phone.tap(try row("Ari", in: phone))
        let ari = try fixture.record(of: kids[0], on: monday)
        #expect(ari.status == .absent && ari.absenceReason == .sick)
        #expect(try row("Ari", in: phone).absenceReason == .sick)
    }

    @Test("Taken back, a mark keeps who made it and when")
    func restoredMarkKeepsItsMaker() throws {
        let kids = fixture.classOf(["Ari"])
        let made = try #require(try guide.ensureRecord(for: kids[0], on: monday))
        #expect(guide.updateStatus(made, to: .present))
        let eightOFour = monday.addingTimeInterval(8 * 3_600 + 4 * 60)
        made.markedAt = eightOFour
        #expect(context.safeSave())
        let phone = fixture.model()

        phone.tap(try row("Ari", in: phone))
        #expect(made.status == .unmarked)
        phone.tap(try row("Ari", in: phone))
        #expect(made.status == .present)
        #expect(made.markedAt == eightOFour)
        #expect(made.recordedBy == CDClassroomMembership.ClassroomRole.leadGuide.rawValue)
    }

    @Test("Late: a stray tap on an absence with a reason comes back with the reason")
    func strayTapDuringLate() throws {
        let kids = fixture.classOf(["Ari", "Maya"])
        let phone = fixture.model()
        phone.markAbsent(reason: .vacation, for: try row("Ari", in: phone))
        #expect(phone.beginLate() == 1)

        phone.tap(try row("Ari", in: phone))
        #expect(try row("Ari", in: phone).status == .tardy)
        phone.tap(try row("Ari", in: phone))
        #expect(try fixture.record(of: kids[0], on: monday).absenceReason == .vacation)
    }

    @Test("Another tile's tap, a menu, an import or a reopen leaves the tap cycle as it was")
    func restoreIsOnlyForTheLastTap() throws {
        let kids = fixture.classOf(["Ari", "Maya"])
        let phone = fixture.model()
        let ari = { try self.row("Ari", in: phone) }

        // Another tile's tap in between.
        phone.markAbsent(reason: .sick, for: try ari())
        phone.tap(try ari())
        phone.tap(try row("Maya", in: phone))
        phone.tap(try ari())
        #expect(try ari().status == .unmarked)

        // A menu change in between.
        phone.markAbsent(reason: .sick, for: try ari())
        phone.tap(try ari())
        phone.setStatus(.tardy, for: try ari())
        phone.tap(try ari())
        #expect(try ari().status == .present)

        // An import that changed the record.
        phone.markAbsent(reason: .sick, for: try ari())
        phone.tap(try ari())
        #expect(guide.updateStatus(try fixture.record(of: kids[0], on: monday), to: .tardy))
        #expect(context.safeSave())
        phone.load()
        phone.tap(try ari())
        #expect(try ari().status == .present)

        // Reopen Arrival in between: a tap then marks him present, not
        // back to Close Arrival's absence.
        phone.setStatus(.unmarked, for: try ari())
        #expect(phone.beginLate() == 1)
        phone.tap(try ari())
        #expect(try ari().status == .tardy)
        phone.returnToArrival()
        phone.tap(try ari())
        #expect(try ari().status == .present)
    }

    // MARK: - #4 The email follows only a close that worked

    @Test("Mark N Absent & Email opens the email only when arrival closed with nobody left unmarked")
    func emailOnlyAfterAClose() throws {
        fixture.classOf(["Ari", "Maya"])
        let phone = fixture.model()
        #expect(phone.beginLate() == 2)
        #expect(phone.emailCanFollowClose())

        let tuesday = try AssistantTestSupport.day("2031-01-07")
        let locked = fixture.model(on: tuesday)
        #expect(AttendanceDayLocks.setLocked(true, for: tuesday, role: .leadGuide, in: context))
        #expect(locked.beginLate() == 0)
        #expect(!locked.emailCanFollowClose())
        #expect(locked.isLocked)
    }

    // MARK: - #6 Smaller

    @Test("A tap that changes nothing says so, so the Undo stays")
    func tapThatDoesNothing() throws {
        fixture.classOf(["Ari", "Maya"])
        let phone = fixture.model()
        #expect(phone.tap(try row("Ari", in: phone)))
        #expect(phone.beginLate() == 1)
        #expect(!phone.tap(try row("Ari", in: phone)), "a present child during Late")
        #expect(phone.tap(try row("Maya", in: phone)))
    }

    @Test("Back to Late with nobody unmarked queues no ParentLocker send")
    func backToLateSendsNothing() {
        #expect(!AssistantArrivalBar.sendsOnClose(unmarked: 0, closesWithSend: true))
        #expect(AssistantArrivalBar.sendsOnClose(unmarked: 2, closesWithSend: true))
        #expect(!AssistantArrivalBar.sendsOnClose(unmarked: 2, closesWithSend: false))
    }

    @Test("On the class's first day, her first mark shows First Day without a reload")
    func firstDayCountsAfterHerMark() throws {
        fixture.classOf(["Ari"])
        let phone = fixture.model()
        #expect(phone.dayNumber == nil)
        phone.tap(try row("Ari", in: phone))
        #expect(phone.dayNumber == 1)
        #expect(phone.milestone == .firstDay)
    }

    @Test("VoiceOver calls a late mark late, as the screen does")
    func voiceOverSaysLate() {
        #expect(AttendanceTile.voiceOverHint(tapTarget: .tardy, reason: "") == "Double tap to mark late")
    }
}

// MARK: - #6 Days off, locks and records from the classroom share only

extension AssistantIdentitySuites {

    @Suite("Assistant grid on two stores (Fix1020 Gr)")
    @MainActor
    struct AssistantSplitStoreFix1020GrTests {

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

        @Test("A notebook of her own on the same Apple Account doesn't lock, close or mark the class's day")
        func privateStoreStaysOut() throws {
            let context = try splitContext()
            let shared = try store(CoreDataStack.sharedConfiguration, in: context)
            let mine = try store(CoreDataStack.privateConfiguration, in: context)
            let wednesday = try AssistantTestSupport.day("2031-01-08")
            let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
            context.assign(ari, to: shared)

            // Her own notebook's lock, day off, and a mark for the same child id.
            let lock = CDAttendanceDayLock(context: context)
            lock.date = wednesday
            context.assign(lock, to: mine)
            let holiday = CDNonSchoolDay(context: context)
            holiday.date = wednesday
            holiday.reason = "Her own day off"
            context.assign(holiday, to: mine)
            let own = CDAttendanceRecord(context: context)
            own.studentID = try #require(ari.id?.uuidString)
            own.date = wednesday
            own.status = .absent
            own.absenceReasonRaw = AttendanceDeduplication.automaticAbsenceRaw
            context.assign(own, to: mine)
            #expect(context.safeSave())

            let model = grid(context, on: wednesday)
            #expect(model.dayOff == nil)
            #expect(!model.isLocked && model.canMark)
            #expect(model.rows.first?.status == .unmarked)
            #expect(model.phase == .arrival)

            // Her mark goes to the share, and two looks before a save find one record.
            let store = CDAttendanceStore(context: context, role: .assistant)
            let first = try #require(try store.ensureRecord(for: ari, on: wednesday))
            #expect(try store.ensureRecord(for: ari, on: wednesday) === first)
            #expect(first.objectID.persistentStore == shared)
        }

        @Test("The class's own day off and lock still show")
        func sharedStoreCounts() throws {
            let context = try splitContext()
            let shared = try store(CoreDataStack.sharedConfiguration, in: context)
            let thursday = try AssistantTestSupport.day("2031-01-09")
            context.assign(AssistantTestSupport.student("Ari", "Cedar", in: context), to: shared)
            let holiday = CDNonSchoolDay(context: context)
            holiday.date = thursday
            holiday.reason = "Staff day"
            context.assign(holiday, to: shared)
            let lock = CDAttendanceDayLock(context: context)
            lock.date = thursday
            context.assign(lock, to: shared)
            #expect(context.safeSave())

            let model = grid(context, on: thursday)
            #expect(model.dayOff == .holiday("Staff day"))
            #expect(model.isLocked)
        }
    }
}
