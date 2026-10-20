import Foundation
import CoreData
import Testing
import UserNotifications
@testable import Daybook_Assistant

// The front desk and ParentLocker after the 2026-10-20 bug hunt (plan
// "Daybook Assistant bug hunt 2026-10-20 fixes", agent FD): a reminder tap
// waits for iCloud before emailing again (#14), the line names the first
// send (#15), ParentLocker tries again when the network comes back (#16),
// Send to ParentLocker only for today and never on a day it isn't expecting
// (#17, #19), old notifications leave today alone and a send clears the
// day's (#18), and the send goes on the composer's day, with Mail's failure
// said (#20). The reminders' own fixes are in `AssistantRemindersFix1020FD`.
@Suite("Assistant fixes 2026-10-20: front desk and ParentLocker")
@MainActor
struct AssistantFix1020FD {

    /// The Monday these tests take for today, whatever day they run.
    private static func monday() throws -> Date { try AssistantTestSupport.day("2026-10-12") }

    /// "8:42 AM" on `day`.
    private static func time(_ hour: Int, _ minute: Int, on day: Date) -> Date {
        day.addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }

    /// Ari and Maya, both marked present on the Monday, with `method` picked,
    /// seen at 8:50 that Monday.
    private func classMarkedIn(
        _ method: AttendanceSendMethod, seenOn seen: Date? = nil
    ) throws -> (CoreDataStack, AssistantAttendanceViewModel) {
        let monday = try Self.monday()
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let store = CDAttendanceStore(context: context, role: .assistant)
        for (first, last) in [("Ari", "Cedar"), ("Maya", "Stone")] {
            let child = AssistantTestSupport.student(first, last, in: context)
            let record = try #require(try store.ensureRecord(for: child, on: monday))
            #expect(store.updateStatus(record, to: .present))
        }
        #expect(context.safeSave())
        ParentLockerTestSettings.pick(method, in: context)
        let model = AssistantTestSupport.viewModel(
            stack, on: monday, now: seen ?? Self.time(8, 50, on: monday)
        )
        return (stack, model)
    }

    /// Waits until `condition` holds, for up to `seconds`.
    private func eventually(seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - #14: a reminder tap waits for iCloud

    @Test("A reminder tap that brought the app forward waits for iCloud's import, then sees the send it brought (#14)",
          .timeLimit(.minutes(1)))
    func reminderTapWaitsForTheImport() async throws {
        let (stack, model) = try classMarkedIn(.email)
        let monday = try Self.monday()
        #expect(AssistantFrontDeskMail.reminderAction(for: model) == .openEmail, "nobody has sent it here yet")

        let (imports, arrived) = AsyncStream.makeStream(of: Void.self)
        let decision = Task {
            await AssistantFrontDeskMail.reminderActionAfterCatchUp(
                viewModel: model, broughtForward: true, now: Self.time(8, 50, on: monday), limit: .seconds(30)
            ) {
                for await _ in imports { return }
            }
        }
        #expect(await eventually { model.frontDesk.isCheckingForSend }, "the bar says it's checking")

        // Another assistant sent it a minute ago; it arrives with the import.
        let send = AttendanceEmailLog.recordSend(
            on: monday, role: .assistant, now: Self.time(8, 49, on: monday), in: stack.viewContext
        )
        send.sentByName = "Ava"
        #expect(stack.viewContext.safeSave())
        arrived.yield()

        #expect(await decision.value == .nothing, "no second email to the front desk")
        #expect(!model.frontDesk.isCheckingForSend)
    }

    @Test("With no import, the wait ends at its limit; a tap with the app already open doesn't wait (#14)",
          .timeLimit(.minutes(1)))
    func reminderWaitHasALimit() async throws {
        let (_, model) = try classMarkedIn(.email)
        let monday = try Self.monday()
        let never: @Sendable () async -> Void = {
            let (silence, _) = AsyncStream.makeStream(of: Void.self)
            for await _ in silence { return }
        }

        let started = ContinuousClock.now
        let limited = await AssistantFrontDeskMail.reminderActionAfterCatchUp(
            viewModel: model, broughtForward: true, now: Self.time(8, 50, on: monday), limit: .milliseconds(200),
            firstImport: never
        )
        #expect(limited == .openEmail)
        #expect(ContinuousClock.now - started >= .milliseconds(200), "it waited")
        #expect(!model.frontDesk.isCheckingForSend)

        let quick = ContinuousClock.now
        let atOnce = await AssistantFrontDeskMail.reminderActionAfterCatchUp(
            viewModel: model, broughtForward: false, now: Self.time(8, 50, on: monday), limit: .seconds(20),
            firstImport: never
        )
        #expect(atOnce == .openEmail)
        #expect(ContinuousClock.now - quick < .seconds(5), "no wait with the app already open")
    }

    @Test("A tap counts as bringing the app forward unless it had been open a moment already (#14)")
    func broughtForwardRule() {
        let now = Date()
        #expect(ArrivalReminderTaps.broughtForward(activeSince: nil, now: now))
        #expect(ArrivalReminderTaps.broughtForward(activeSince: now.addingTimeInterval(-0.5), now: now))
        #expect(!ArrivalReminderTaps.broughtForward(activeSince: now.addingTimeInterval(-60), now: now))
    }

    // MARK: - #15: the line names the first send

    @Test("Send Again keeps the first send's sender and on-time, and adds when it went again (#15)")
    func summaryFromTheFirstSend() throws {
        let (stack, model) = try classMarkedIn(.email)
        let context = stack.viewContext
        let monday = try Self.monday()
        let onTime = AttendanceEmailLog.recordSend(
            on: monday, role: .assistant, now: Self.time(8, 42, on: monday), in: context
        )
        onTime.sentByName = "Sarah"
        let again = AttendanceEmailLog.recordSend(
            on: monday, role: .assistant, now: Self.time(9, 15, on: monday), in: context
        )
        again.sentByName = "Ava"
        #expect(context.safeSave())
        model.load()

        let frontDesk = model.frontDesk
        #expect(frontDesk.latestSend?.sentByName == "Ava", "the newest send still decides that the day has gone")
        let sends = try #require(frontDesk.daySends)
        #expect(sends.first.sentByName == "Sarah")
        let first = AttendanceEmailLog.Send.time(Self.time(8, 42, on: monday), reporting: monday)
        let second = AttendanceEmailLog.Send.time(Self.time(9, 15, on: monday), reporting: monday)
        #expect(sends.summary(senderName: "Sarah", for: monday, deadlineMinutes: frontDesk.deadlineMinutes)
            == "Emailed \(first) by Sarah · sent again \(second)")
    }

    @Test("A send the other way starts the line again: who and when come from that way's first (#15)")
    func summaryFollowsTheNewestWay() throws {
        let (stack, _) = try classMarkedIn(.parentLocker)
        let context = stack.viewContext
        let monday = try Self.monday()
        AttendanceEmailLog.recordSend(on: monday, role: .assistant, now: Self.time(8, 42, on: monday), in: context)
        let locker = AttendanceEmailLog.recordSend(
            on: monday, role: .assistant, channel: .parentLocker, now: Self.time(9, 30, on: monday), in: context
        )
        locker.sentByName = "Ava"
        #expect(context.safeSave())

        let sends = try #require(AttendanceEmailLog.daySends(on: monday, in: context))
        #expect(sends.first.channel == .parentLocker)
        #expect(sends.again == nil)
        let when = AttendanceEmailLog.Send.time(Self.time(9, 30, on: monday), reporting: monday)
        #expect(sends.summary(senderName: "Ava", for: monday, deadlineMinutes: 540)
            == "Sent to ParentLocker \(when) by Ava (late)")
    }

    // MARK: - #16: ParentLocker tries again when the network comes back

    @Test("The network coming back runs ParentLocker's return; a move between Wi-Fi and cellular doesn't (#16)",
          .timeLimit(.minutes(1)))
    func networkReturnReachesParentLocker() async throws {
        typealias Path = AssistantNetworkWatch.PathState
        let wifi = Path(usable: true, interface: .wifi)
        let cellular = Path(usable: true, interface: .cellular)
        let offline = Path(usable: false, interface: .other)
        let counts = Counts()
        let (paths, feed) = AsyncStream.makeStream(of: Path.self)
        let watch = AssistantNetworkWatch(
            paths: paths, settle: .milliseconds(100),
            retry: { counts.retries += 1 },
            cameBack: { counts.returns += 1 }
        )
        defer { watch.stop() }

        feed.yield(wifi) // the first path only sets the scene
        feed.yield(cellular)
        #expect(await eventually { counts.retries == 1 })
        try await Task.sleep(for: .milliseconds(300))
        #expect(counts.returns == 0, "a move between links isn't the network coming back")

        feed.yield(offline)
        feed.yield(wifi)
        #expect(await eventually { counts.retries == 2 })
        #expect(await eventually { counts.returns == 1 })

        // Back, then onto cellular within the settle time: one of each.
        feed.yield(offline)
        feed.yield(wifi)
        feed.yield(cellular)
        #expect(await eventually { counts.retries == 3 })
        #expect(await eventually { counts.returns == 2 })
        try await Task.sleep(for: .milliseconds(300))
        #expect(counts.retries == 3)
        #expect(counts.returns == 2)
    }

    // MARK: - #17, #19: Send to ParentLocker

    @Test("Send to ParentLocker is offered for today, not for an earlier day nobody sent (#17)")
    func sendOfferedOnlyToday() throws {
        let (_, today) = try classMarkedIn(.parentLocker)
        #expect(today.isToday)
        #expect(today.frontDesk.offersParentLockerSend(by: today))

        let tuesday = try AssistantTestSupport.day("2026-10-13")
        let (_, later) = try classMarkedIn(.parentLocker, seenOn: Self.time(9, 0, on: tuesday))
        #expect(!later.isToday)
        #expect(later.frontDesk.offersParentLocker(by: later), "the line still shows, with Send Now in its menu")
        #expect(!later.frontDesk.offersParentLockerSend(by: later))
    }

    @Test("Another day's Send Now asks first, in plain words (#17)")
    func otherDaySendAsks() throws {
        let monday = try Self.monday()
        #expect(AssistantParentLockerSendStep.confirmsDay(isToday: false))
        #expect(!AssistantParentLockerSendStep.confirmsDay(isToday: true))
        let title = ParentLockerStatus.otherDaySendTitle(for: monday)
        #expect(title.hasPrefix("Send Monday"))
        #expect(title.hasSuffix(" to ParentLocker?"))
        #expect(ParentLockerStatus.otherDaySendMessage(unmarked: [])
            == "This replaces what the office has for that day.")
        #expect(ParentLockerStatus.otherDaySendMessage(unmarked: ["Maya S"])
            == "This replaces what the office has for that day. Maya S isn't marked; the rest go.")
    }

    @Test("On a day ParentLocker isn't expecting, Send to ParentLocker isn't offered (#19)")
    func notExpectedDayOffersNoSend() throws {
        let (stack, model) = try classMarkedIn(.parentLocker)
        #expect(model.frontDesk.offersParentLockerSend(by: model))

        AttendanceEmailLog.recordNotExpected(on: model.date, role: .assistant, in: stack.viewContext)
        #expect(stack.viewContext.safeSave())
        model.load()
        #expect(model.frontDesk.latestSend == nil, "a note, not a send")
        #expect(!model.frontDesk.offersParentLockerSend(by: model))
    }

    // MARK: - #18: old notifications and delivered ones

    @Test("A reminder tapped on a later day is about that day, not today (#18)")
    func oldTapsAreNotToday() throws {
        let monday = try Self.monday()
        let tuesday = try AssistantTestSupport.day("2026-10-13")
        let now = Self.time(9, 30, on: tuesday)
        let mondayID = AppCalendar.dayID(monday)
        let tuesdayID = AppCalendar.dayID(tuesday)

        #expect(ArrivalReminderTaps.isForToday("arrival-" + tuesdayID, now: now))
        #expect(!ArrivalReminderTaps.isForToday("arrival-" + mondayID, now: now))
        #expect(ArrivalReminderTaps.isForToday("frontdesk-" + tuesdayID + "-due", now: now))
        #expect(!ArrivalReminderTaps.isForToday("frontdesk-" + mondayID + "-soon", now: now))
        // A pickup's tap only shows today, as before.
        #expect(ArrivalReminderTaps.isForToday("pickup-abc-" + mondayID + "-810", now: now))
    }

    @Test("Once the day is sent, its delivered front-desk notifications are cleared (#18)")
    func sendClearsDeliveredNotifications() async throws {
        let (stack, _) = try classMarkedIn(.email)
        let monday = try Self.monday()
        let center = DeliveredReminderCenter()
        let early = Self.time(7, 0, on: monday)

        await FrontDeskEmailReminder.reschedule(in: stack.viewContext, now: early, center: center)
        #expect(center.removedDelivered.isEmpty, "nothing has gone yet")

        let context = stack.viewContext
        AttendanceEmailLog.recordSend(on: monday, role: .assistant, now: Self.time(8, 40, on: monday), in: context)
        #expect(context.safeSave())
        await FrontDeskEmailReminder.reschedule(in: context, now: Self.time(9, 5, on: monday), center: center)
        let day = AppCalendar.dayID(monday)
        #expect(Set(center.removedDelivered) == ["frontdesk-\(day)-soon", "frontdesk-\(day)-due"])
    }

    // MARK: - #20: the composer's day and Mail's failure

    @Test("The send is recorded on the day the email was opened for, even after the grid moved (#20)")
    func sendRecordedOnTheComposersDay() throws {
        let monday = try Self.monday()
        let tuesday = try AssistantTestSupport.day("2026-10-13")
        let (stack, model) = try classMarkedIn(.email, seenOn: Self.time(9, 0, on: tuesday))
        #expect(model.date == monday)
        // The email opened for Monday; a tapped reminder moved the grid to today.
        model.load(tuesday)
        model.frontDesk.recordSend(confirmedByHand: false, on: monday)

        #expect(AttendanceEmailLog.latestSend(on: monday, in: stack.viewContext) != nil)
        #expect(AttendanceEmailLog.latestSend(on: tuesday, in: stack.viewContext) == nil)
        #expect(model.frontDesk.latestSend == nil, "today on screen hasn't gone")
    }

    @Test("A send Mail says failed says so plainly, and a send that works clears it (#20)")
    func mailFailureIsSaid() throws {
        let (_, model) = try classMarkedIn(.email)
        model.frontDesk.mailFailed()
        #expect(model.frontDesk.errorMessage == "The email didn't send. Try again.")
        model.frontDesk.recordSend(confirmedByHand: false)
        #expect(model.frontDesk.errorMessage == nil)
    }
}

// MARK: - The ParentLocker sync's read of a closed day

// Gr's #2 rule reaches the ParentLocker sync too: the day it reads stays
// closed once Close Arrival's absences are resolved, and opens on an Undo.
extension AssistantFix1020FD {

    @Test("ParentLocker reads arrival closed by #2's rule: resolving the absences keeps it closed, an Undo opens it")
    func parentLockerFollowsTheSeenClose() throws {
        let monday = try Self.monday()
        for undoes in [false, true] {
            let stack = try AssistantTestSupport.makeStack()
            let context = stack.viewContext
            let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
            let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
            ParentLockerTestSettings.pick(.parentLocker, in: context)
            // The guide closes arrival on the Mac.
            let attendance = CDAttendanceStore(context: context, role: .leadGuide)
            let closed = try attendance.markUnmarkedAbsent(for: monday, students: [ari, maya])
            #expect(context.safeSave())
            let store = ParentLockerCoreDataStore(context: context, lateDefaults: AssistantTestSupport.makeDefaults())
            #expect(store.day(monday, withChildren: false).arrivalClosed)

            let ariRecord = try #require(closed.first { $0.studentID == ari.id?.uuidString })
            let mayaRecord = try #require(closed.first { $0.studentID == maya.id?.uuidString })
            if undoes {
                for record in closed { attendance.undoAutomaticAbsence(record) }
            } else {
                // Maya arrives late; Ari is home sick. No automatic absence is left.
                attendance.updateStatus(mayaRecord, to: .tardy)
                attendance.updateAbsenceReason(ariRecord, to: .sick)
            }
            #expect(context.safeSave())
            #expect(store.day(monday, withChildren: false).arrivalClosed == !undoes)
        }
    }
}

/// What a network watch under test asked for.
@MainActor
private final class Counts {
    var retries = 0
    var returns = 0
}

/// A center that remembers which delivered notifications were cleared.
@MainActor
private final class DeliveredReminderCenter: ReminderCenter {
    let inner = FakeReminderCenter()
    private(set) var removedDelivered: [String] = []

    func authorizationStatus() async -> UNAuthorizationStatus { await inner.authorizationStatus() }
    func requestAuthorization() async -> Bool { await inner.requestAuthorization() }
    func pendingRequests() async -> [UNNotificationRequest] { await inner.pendingRequests() }
    func removePendingRequests(withIdentifiers identifiers: [String]) {
        inner.removePendingRequests(withIdentifiers: identifiers)
    }
    func add(_ request: UNNotificationRequest) async throws { try await inner.add(request) }
    func removeDeliveredRequests(withIdentifiers identifiers: [String]) {
        removedDelivered += identifiers
    }
}
