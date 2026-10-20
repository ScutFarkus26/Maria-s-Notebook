import Foundation
import CoreData
import Testing
import UserNotifications
@testable import Daybook_Assistant

// The fix round after review (c) of the front-desk fixes (plan "Daybook
// Assistant bug hunt 2026-10-20 fixes", Phase 2). Each test names the
// review's item.
@Suite("Assistant fixes 2026-10-20: review (c) round")
@MainActor
struct AssistantFix1020RoundC {

    /// The Monday these tests take for today, whatever day they run.
    private static func monday() throws -> Date { try AssistantTestSupport.day("2026-10-12") }

    /// "8:42 AM" on `day`.
    private static func time(_ hour: Int, _ minute: Int, on day: Date) -> Date {
        day.addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }

    /// Waits until `condition` holds, for up to 5 s.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Ari marked present and Maya not yet marked on the Monday, the email
    /// picked, seen at `hour`:`minute` that Monday.
    private func classArriving(
        at hour: Int = 8, _ minute: Int = 45
    ) throws -> (CoreDataStack, AssistantAttendanceViewModel) {
        let monday = try Self.monday()
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let store = CDAttendanceStore(context: context, role: .assistant)
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        let record = try #require(try store.ensureRecord(for: ari, on: monday))
        #expect(store.updateStatus(record, to: .present))
        #expect(context.safeSave())
        ParentLockerTestSettings.pick(.email, in: context)
        let model = AssistantTestSupport.viewModel(stack, on: monday, now: Self.time(hour, minute, on: monday))
        return (stack, model)
    }

    // MARK: - 1 and #17: another day's Send Now

    @Test("Another day's Send Now asks first, naming the unmarked; her yes sends that day, no second question (1, #17)")
    func otherDaySendNowGate() throws {
        let monday = try Self.monday()
        typealias Step = AssistantParentLockerSendStep
        let signedIn = FakeParentLockerSender(unmarked: ["Maya S"])

        let step = Step.first(on: monday, isToday: false, unmarkedConfirmed: false, sync: signedIn)
        #expect(step == .confirmDay(unmarked: ["Maya S"]))
        let question = Step.Question(day: monday, isToday: false, step: step)
        #expect(question.unmarked == ["Maya S"])
        #expect(question.answered(sync: signedIn) == .send, "the day's question named Maya already")
        #expect(question.day == monday)

        // Today goes as before: the unmarked question, then the send.
        let today = Step.first(on: monday, isToday: true, unmarkedConfirmed: false, sync: signedIn)
        #expect(today == .ask(unmarked: ["Maya S"]))
        #expect(Step.Question(day: monday, isToday: true, step: today).answered(sync: signedIn) == .send)
        #expect(Step.first(on: monday, isToday: true, unmarkedConfirmed: false, sync: FakeParentLockerSender())
            == .send, "today, everyone marked: one tap")

        // Not signed in, another day only opens the sign-in: nothing goes yet.
        let signedOut = FakeParentLockerSender(isSignedIn: false)
        #expect(Step.first(on: monday, isToday: false, unmarkedConfirmed: false, sync: signedOut) == .signIn)
    }

    // MARK: - 2: an Undo, then a child marked present, seen at once

    @Test("Seen closed, then an Undo and Ari marked present, seen in one import: Arrival, not Late (2)")
    func undoThenPresentReopens() throws {
        let fixture = try AssistantGridFixture()
        let kids = fixture.classOf(["Ari", "Maya"])
        let monday = fixture.monday
        let phone = fixture.model()
        #expect(try fixture.guide.markUnmarkedAbsent(for: monday, students: kids).count == 2)
        #expect(fixture.context.safeSave())
        phone.load()
        #expect(phone.phase == .late)

        // Another device's Undo, then Ari marked present as arrival goes on:
        // this phone missed the moment both were unmarked.
        for child in kids { #expect(fixture.guide.undoAutomaticAbsence(try fixture.record(of: child, on: monday))) }
        #expect(fixture.guide.updateStatus(try fixture.record(of: kids[0], on: monday), to: .present))
        #expect(fixture.context.safeSave())
        phone.load()
        #expect(phone.phase == .arrival)
        #expect(phone.statusAfterTap(for: try fixture.row("Maya", in: phone)) == .present)
    }

    @Test("Every remembered child present again reads as an Undo too; one marked late keeps Late (2)")
    func allPresentIsAnUndoButLateIsNot() throws {
        let fixture = try AssistantGridFixture()
        let kids = fixture.classOf(["Ari", "Maya"])
        let monday = fixture.monday
        let phone = fixture.model()
        #expect(try fixture.guide.markUnmarkedAbsent(for: monday, students: kids).count == 2)
        #expect(fixture.context.safeSave())
        phone.load()

        // Maya arrives after the close: Late, so the day stays closed.
        #expect(fixture.guide.updateStatus(try fixture.record(of: kids[1], on: monday), to: .tardy))
        #expect(fixture.guide.updateAbsenceReason(try fixture.record(of: kids[0], on: monday), to: .sick))
        #expect(fixture.context.safeSave())
        phone.load()
        #expect(phone.phase == .late)

        let other = try AssistantGridFixture()
        let pair = other.classOf(["Ari", "Maya"])
        let seen = other.model()
        #expect(try other.guide.markUnmarkedAbsent(for: other.monday, students: pair).count == 2)
        #expect(other.context.safeSave())
        seen.load()
        for child in pair {
            #expect(other.guide.undoAutomaticAbsence(try other.record(of: child, on: other.monday)))
            #expect(other.guide.updateStatus(try other.record(of: child, on: other.monday), to: .present))
        }
        #expect(other.context.safeSave())
        seen.load()
        #expect(seen.phase == .arrival)
    }

    @Test("ParentLocker's day reads open after an Undo and a present mark seen together, so no backstop (2)")
    func parentLockerReadsTheUndoThenPresent() throws {
        let monday = try Self.monday()
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        ParentLockerTestSettings.pick(.parentLocker, in: context)
        let phone = CDAttendanceStore(context: context, role: .assistant)
        let closed = try phone.markUnmarkedAbsent(for: monday, students: [ari, maya])
        #expect(context.safeSave())
        // The guide's Mac sees the close.
        let mac = ParentLockerCoreDataStore(
            context: context, fixedRole: .leadGuide, lateDefaults: AssistantTestSupport.makeDefaults()
        )
        #expect(mac.day(monday, withChildren: false).arrivalClosed)

        for record in closed { #expect(phone.undoAutomaticAbsence(record)) }
        let ariRecord = try #require(closed.first { $0.studentID == ari.id?.uuidString })
        #expect(phone.updateStatus(ariRecord, to: .present))
        #expect(context.safeSave())
        #expect(!mac.day(monday, withChildren: false).arrivalClosed)
    }

    // MARK: - 3: a sample rebuild queued behind another

    @Test("A sample rebuild queued when she leaves the sample files nothing under the real class (3)",
          .timeLimit(.minutes(1)))
    func queuedSampleRebuildAfterLeaving() async throws {
        let wasChosen = AssistantSampleClass.isChosen
        defer { AssistantSampleClass.isChosen = wasChosen }
        AssistantSampleClass.isChosen = true
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        try pickupTomorrow(in: context)
        let center = HeldFirstReadCenter()

        // One rebuild of the sample's is going; another is asked for as the
        // sample's own (nil: whose is read when it's asked for).
        let first = Task {
            await EarlyPickupReminder.reschedule(in: context, asksPermission: false, isSample: true, center: center)
        }
        #expect(await eventually { center.isHolding })
        let queued = Task { await EarlyPickupReminder.reschedule(in: context, asksPermission: false, center: center) }
        try await Task.sleep(for: .milliseconds(100))

        // She leaves the sample.
        AssistantSampleClass.isChosen = false
        let leave = Task { await EarlyPickupReminder.cancelSample(center: center) }
        try await Task.sleep(for: .milliseconds(100))
        center.open()
        await first.value
        await queued.value
        await leave.value

        #expect(center.inner.ids("pickup-").isEmpty, "no sample child rings as the real class's")
    }

    // MARK: - 4: "The email didn't send" goes once it has

    @Test("Mail's failure line goes once the email has gone from another phone, or the day changes (4)")
    func mailFailureLineClears() throws {
        let (stack, model) = try classArriving(at: 8, 50)
        let context = stack.viewContext
        let monday = try Self.monday()
        let frontDesk = model.frontDesk

        frontDesk.mailFailed()
        model.load()
        #expect(frontDesk.errorMessage != nil, "nothing has gone: it still says so after a reload")

        let send = AttendanceEmailLog.recordSend(
            on: monday, role: .assistant, now: Self.time(8, 52, on: monday), in: context
        )
        send.sentByName = "Ava"
        #expect(context.safeSave())
        model.load()
        #expect(frontDesk.errorMessage == nil, "Ava's email went")

        frontDesk.mailFailed()
        model.load()
        #expect(frontDesk.errorMessage != nil, "a failed Send Again stays until something newer")
        model.load(try AssistantTestSupport.day("2026-10-13"))
        #expect(frontDesk.errorMessage == nil, "another day")
    }

    // MARK: - 5: the plain Close Arrival while a tap checks

    @Test("While a tapped reminder checks, the bar keeps the plain Close Arrival (5)", .timeLimit(.minutes(1)))
    func plainCloseArrivalWhileChecking() async throws {
        let (_, model) = try classArriving(at: 8, 45)
        let monday = try Self.monday()
        let now = Self.time(8, 45, on: monday)
        #expect(model.frontDesk.offersCloseAndEmail(by: model, now: now))

        let check = Task {
            await model.frontDesk.waitForCatchUp(limit: .milliseconds(500)) {
                let (silence, _) = AsyncStream.makeStream(of: Void.self)
                for await _ in silence { return }
            }
        }
        #expect(await eventually { model.frontDesk.isCheckingForSend })
        #expect(!model.frontDesk.offersCloseAndEmail(by: model, now: now), "Close Arrival & Email steps aside")
        await check.value
        #expect(model.frontDesk.offersCloseAndEmail(by: model, now: now))
    }

    @Test("A tap doesn't wait once an import into the class's store, begun since the app came forward, finished (5)")
    func catchUpSkipsAFinishedImport() {
        let forward = Date()
        var record = AssistantCatchUpRecord(forwardSince: forward)
        func waits(_ broughtForward: Bool = true, store: String? = "class") -> Bool {
            AssistantFrontDeskMail.waitsForCatchUp(broughtForward: broughtForward, storeID: store, record: record)
        }
        #expect(waits())
        #expect(!waits(false), "a tap with the app already open decides at once")
        #expect(!waits(store: nil), "the Sample Class has nothing to wait for")

        record.importFinished(into: "class", startedAt: forward.addingTimeInterval(-30))
        #expect(waits(), "begun before the app came forward: it may hold nothing from while she was away")
        record.importFinished(into: "own", startedAt: forward.addingTimeInterval(1))
        #expect(waits(), "her own notebook's store isn't the class's")
        record.importFinished(into: "class", startedAt: forward.addingTimeInterval(1))
        #expect(!waits(), "the class's import finished before the screen listened: no wait")

        record.cameForward(at: forward.addingTimeInterval(3_600))
        #expect(waits(), "back from the background later: that import may be behind")
    }

    @Test("A tapped front-desk reminder for today asks for the email and says whether it brought the app forward (#14)")
    func reminderTapWiring() throws {
        let wasRequested = FrontDeskEmailReminder.isEmailRequested
        let wasForward = AssistantFrontDeskMail.tapBroughtAppForward
        defer {
            FrontDeskEmailReminder.isEmailRequested = wasRequested
            AssistantFrontDeskMail.tapBroughtAppForward = wasForward
        }
        let now = Date()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))

        FrontDeskEmailReminder.isEmailRequested = false
        ArrivalReminderTaps.handleTap(try #require(FrontDeskEmailReminder.identifiers(on: yesterday).first), now: now)
        #expect(!FrontDeskEmailReminder.isEmailRequested, "yesterday's only opens the app")

        AssistantFrontDeskMail.tapBroughtAppForward = false
        ArrivalReminderTaps.handleTap(try #require(FrontDeskEmailReminder.identifiers(on: now).first), now: now)
        #expect(FrontDeskEmailReminder.isEmailRequested)
        #expect(AssistantFrontDeskMail.tapBroughtAppForward
            == ArrivalReminderTaps.broughtForward(activeSince: ArrivalReminderTaps.activeSince, now: now))
    }

    // MARK: - 6: the network's return and the app's

    @Test("The network's return runs ParentLocker's return only when the app's own hasn't just run it (6)")
    func networkReturnLeavesTheAppsReturnAlone() {
        let now = Date()
        let longAgo = now.addingTimeInterval(-600)
        typealias Watch = AssistantNetworkWatch
        #expect(Watch.runsParentLockerReturn(awaitingImport: false, activeSince: longAgo, now: now))
        #expect(Watch.runsParentLockerReturn(awaitingImport: false, activeSince: nil, now: now))
        #expect(!Watch.runsParentLockerReturn(awaitingImport: true, activeSince: longAgo, now: now),
                "the sync already waits for the import the network brings")
        #expect(!Watch.runsParentLockerReturn(awaitingImport: false, activeSince: now.addingTimeInterval(-4), now: now),
                "the app came back seconds ago and ran it then")
    }

    // MARK: - Helpers

    /// Maya, leaving at 1:30 tomorrow.
    private func pickupTomorrow(in context: NSManagedObjectContext) throws {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: today))
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let store = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try store.ensureRecord(for: maya, on: tomorrow))
        store.updateLeavesAt(record, to: tomorrow.addingTimeInterval(13.5 * 3_600))
        #expect(context.safeSave())
        #expect(!EarlyPickupReminder.pendingPickups(in: context).isEmpty)
    }
}

/// A center whose first read of the pending requests waits for `open()`, so
/// a test can hold one rebuild mid-way; every later read goes through.
@MainActor
private final class HeldFirstReadCenter: ReminderCenter {
    let inner = FakeReminderCenter()
    private(set) var isHolding = false
    private var hasHeld = false
    private var isOpen = false
    private var held: CheckedContinuation<Void, Never>?

    func open() {
        isOpen = true
        held?.resume()
        held = nil
    }

    func authorizationStatus() async -> UNAuthorizationStatus { await inner.authorizationStatus() }
    func requestAuthorization() async -> Bool { await inner.requestAuthorization() }

    func pendingRequests() async -> [UNNotificationRequest] {
        if !hasHeld, !isOpen {
            hasHeld = true
            isHolding = true
            await withCheckedContinuation { held = $0 }
        }
        return await inner.pendingRequests()
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        inner.removePendingRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws { try await inner.add(request) }
}
