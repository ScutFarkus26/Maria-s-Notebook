import Foundation
import CoreData
import Testing
import UserNotifications
@testable import Daybook_Assistant

// The 2026-11-03 hunt's front desk, ParentLocker and reminder findings (plan
// "Daybook Assistant bugs and efficiency 2026-11-03 fixes", agent FD): a
// ParentLocker send under way when the stack is rebuilt (#1), one reminder
// refresh asking the notification center once (#16), the due time on the
// days the clocks change (#17), a send record that didn't save (#19), the
// reminders' calendar (#20), and the smaller ParentLocker items (#21).

@Suite("Assistant fixes 2026-11-03: front desk, ParentLocker and reminders")
@MainActor
struct AssistantFix1103FD {

    /// Waits until `condition` holds, for up to 10 s.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - #1: a send under way when the sync stops

    @Test("A sync stopped while its send is under way records no send and leaves what's owed alone (#1)",
          .timeLimit(.minutes(1)))
    func stoppedSyncWritesNothing() async throws {
        let device = FD1103Device()
        let sending = Task { await device.sync.sendNow(day: device.clock.now) }
        #expect(await eventually { device.site.isHoldingSave }, "the save is under way")

        // The rebuild stops the old sync; the new one has saved what it owes since.
        device.sync.stop()
        let newSyncsOwed = ParentLockerUnsent(
            day: AppCalendar.dayID(device.clock.now), children: [UUID()], wholeClass: true
        )
        device.unsent.save(newSyncsOwed)
        device.site.releaseSave()
        _ = await sending.value

        #expect(device.site.saves == 1, "the save itself went through")
        #expect(device.store.recordedSends.isEmpty, "a stopped sync's context may be gone")
        #expect(device.unsent.load() == newSyncsOwed, "the new sync's owed state stands")
    }

    // MARK: - #16, #20: one refresh, one look at the notification center

    /// A class of one, joined, with the guide's email set up and a pickup tomorrow.
    private func classWithPickup() throws -> CoreDataStack {
        let stack = try ReminderTestClass.withEmail()
        let context = stack.viewContext
        let maya = try #require(context.safeFetchFirst(CDFetchRequest(CDStudent.self)))
        let today = AppCalendar.shared.startOfDay(for: Date())
        let tomorrow = try #require(AppCalendar.shared.date(byAdding: .day, value: 1, to: today))
        let store = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try store.ensureRecord(for: maya, on: tomorrow))
        store.updateLeavesAt(record, to: tomorrow.addingTimeInterval(13.5 * 3_600))
        #expect(context.safeSave())
        #expect(!EarlyPickupReminder.pendingPickups(in: context).isEmpty)
        return stack
    }

    @Test("One reminder refresh reads the pending requests and the permission once, for all three kinds (#16)")
    func refreshReadsTheCenterOnce() async throws {
        let stack = try classWithPickup()
        let center = FD1103CountingCenter()

        await EarlyPickupReminderUpkeep.refresh(in: stack.viewContext, isSample: false, center: center)

        #expect(!center.inner.ids("pickup-").isEmpty)
        #expect(!center.inner.ids("arrival-").isEmpty)
        #expect(!center.inner.ids("frontdesk-").isEmpty)
        #expect(center.inner.pendingReads == 1)
        #expect(center.statusReads == 1)
    }

    @Test("Every reminder's trigger carries the app's Gregorian calendar (#20)")
    func triggersCarryTheCalendar() async throws {
        let stack = try classWithPickup()
        let center = FakeReminderCenter()

        await EarlyPickupReminderUpkeep.refresh(in: stack.viewContext, isSample: false, center: center)

        let requests = Array(center.pending.values)
        #expect(!requests.isEmpty)
        for request in requests {
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            #expect(trigger.dateComponents.calendar?.identifier == .gregorian, "\(request.identifier)")
        }
    }

    // MARK: - #17: the due time on the Sundays the clocks change

    nonisolated private static let clockChangeSundays = [
        DateComponents(year: 2026, month: 11, day: 1),
        DateComponents(year: 2027, month: 3, day: 14)
    ]

    private func chicago() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        return calendar
    }

    private func clock(_ hour: Int, _ minute: Int, on sunday: Date, _ calendar: Calendar) throws -> Date {
        try #require(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: sunday))
    }

    @Test("The bar's Due and Late line and when it changes follow the clock on the Sundays the clocks change (#17)",
          arguments: clockChangeSundays)
    func urgencyOnClockChangeDays(day: DateComponents) throws {
        let calendar = try chicago()
        let sunday = try #require(calendar.date(from: day))
        let nine = try clock(9, 0, on: sunday, calendar)

        let due = AttendanceEmailLog.urgency(
            for: sunday, deadlineMinutes: 9 * 60, now: try clock(8, 45, on: sunday, calendar), calendar: calendar
        )
        #expect(due == .due(nine))
        let late = AttendanceEmailLog.urgency(
            for: sunday, deadlineMinutes: 9 * 60, now: try clock(9, 5, on: sunday, calendar), calendar: calendar
        )
        #expect(late == .overdue(nine))
        let changes = AttendanceEmailLog.changeTimes(on: sunday, deadlineMinutes: 9 * 60, calendar: calendar)
        #expect(changes == [try clock(8, 30, on: sunday, calendar), nine])
    }

    @Test("A send says \"(late)\" by the clock on the Sundays the clocks change (#17)")
    func lateByTheClock() throws {
        let calendar = try chicago()
        let context = try AssistantTestSupport.makeStack().viewContext
        let fallBack = try #require(calendar.date(from: Self.clockChangeSundays[0]))
        let springForward = try #require(calendar.date(from: Self.clockChangeSundays[1]))

        let onTime = AttendanceEmailLog.Send(AttendanceEmailLog.recordSend(
            on: fallBack, role: .assistant, now: try clock(8, 30, on: fallBack, calendar), in: context
        ))
        #expect(!onTime.summary(senderName: "Sarah", for: fallBack, deadlineMinutes: 9 * 60, calendar: calendar)
            .hasSuffix("(late)"))
        let late = AttendanceEmailLog.Send(AttendanceEmailLog.recordSend(
            on: springForward, role: .assistant, now: try clock(9, 30, on: springForward, calendar), in: context
        ))
        #expect(late.summary(senderName: "Sarah", for: springForward, deadlineMinutes: 9 * 60, calendar: calendar)
            .hasSuffix("(late)"))
    }

    @Test("The guide's check after the due time counts from 9:00 by the clock (#17)", arguments: clockChangeSundays)
    func parentLockerDeadline(day: DateComponents) throws {
        let calendar = try chicago()
        let sunday = try #require(calendar.date(from: day))
        let deadline = ParentLockerDay(deadlineMinutes: 9 * 60).deadline(on: sunday, calendar: calendar)
        #expect(deadline == (try clock(9, 0, on: sunday, calendar)))
    }

    // MARK: - #19: a send record that didn't save

    @Test("A ParentLocker send or \"not expected\" note that didn't save isn't left in memory (#19)")
    func unsavedRecordIsTakenBack() throws {
        let context = try AssistantTestSupport.makeStack().viewContext
        let day = try AssistantTestSupport.day("2026-10-12")
        let store = ParentLockerCoreDataStore(
            context: context, save: { _, _ in false }, sendRecorded: { _ in }, fixedRole: .assistant
        )

        #expect(!store.recordSend(on: day))
        #expect(AttendanceEmailLog.latestSend(on: day, in: context) == nil)
        #expect(!store.day(day, withChildren: false).sentToParentLocker)

        store.noteNotExpected(on: day)
        #expect(!AttendanceEmailLog.isNotExpected(on: day, in: context))
        #expect(!store.day(day, withChildren: false).notExpected)
    }

    // MARK: - #21: the smaller ParentLocker items

    @Test("Coming back to the app with nobody signed in doesn't delete the cookies again each time (#21)")
    func cookiesDeletedOnlyOnSignOut() {
        let device = FD1103Device(secrets: FD1103Secrets(signedIn: false))
        #expect(!device.sync.isSignedIn)
        let atStart = device.secrets.cookieDeletes

        for _ in 0..<3 { device.sync.appBecameActive() }

        #expect(atStart == 1, "the first look clears any left from before")
        #expect(device.secrets.cookieDeletes == atStart)
    }

    @Test("A mark during arrival reads the day once (#21)")
    func markReadsTheDayOnce() {
        let device = FD1103Device(arrivalClosed: false)
        device.store.reads = 0

        device.sync.noteChanges([FD1103Device.wren], imported: false, on: device.clock.now)

        #expect(device.sync.earlyLocal == [FD1103Device.wren], "kept until arrival closes")
        #expect(device.store.reads == 1)
    }
}

// The fixes' own entry points, added with them.
extension AssistantFix1103FD {

    // MARK: - #1: the rebuild waits for the send

    @Test("The rebuild's wait lets a send under way finish and record, then stops the sync (#1)",
          .timeLimit(.minutes(1)))
    func rebuildWaitsForTheSend() async throws {
        let device = FD1103Device()
        let bootstrapper = AssistantBootstrapper()
        bootstrapper.parentLocker = device.sync
        let sending = Task { await device.sync.sendNow(day: device.clock.now) }
        #expect(await eventually { device.site.isHoldingSave })
        #expect(!(await device.sync.waitForRun(upTo: .milliseconds(200))), "still going at the limit")

        let waiting = Task { await bootstrapper.finishParentLockerBeforeRebuild(upTo: .seconds(10)) }
        device.site.releaseSave()
        await waiting.value
        _ = await sending.value

        #expect(device.store.recordedSends.count == 1, "recorded on the old stack before it went")
        #expect(device.sync.isStopped)
    }

    @Test("A send still going at the rebuild's limit records nothing once it ends (#1)", .timeLimit(.minutes(1)))
    func rebuildGivesUpOnAHangingSend() async throws {
        let device = FD1103Device()
        let bootstrapper = AssistantBootstrapper()
        bootstrapper.parentLocker = device.sync
        let sending = Task { await device.sync.sendNow(day: device.clock.now) }
        #expect(await eventually { device.site.isHoldingSave })

        await bootstrapper.finishParentLockerBeforeRebuild(upTo: .milliseconds(200))
        #expect(device.sync.isStopped)
        device.site.releaseSave()
        _ = await sending.value

        #expect(device.store.recordedSends.isEmpty)
    }

    // MARK: - #18: the front desk's one read

    @Test("The front desk's one read of the day gives what the three reads did (#18)")
    func frontDeskReadsTheDayOnce() throws {
        let context = try AssistantTestSupport.makeStack().viewContext
        let day = try AssistantTestSupport.day("2026-10-12")
        let empty = AttendanceEmailLog.dayRecords(on: day, in: context)
        #expect(empty.latestSend == nil && empty.daySends == nil && !empty.isNotExpected)

        AttendanceEmailLog.recordSend(on: day, role: .assistant, now: day.addingTimeInterval(8.7 * 3_600), in: context)
        AttendanceEmailLog.recordNotExpected(
            on: day, role: .assistant, now: day.addingTimeInterval(9 * 3_600), in: context
        )
        AttendanceEmailLog.recordSend(on: day, role: .assistant, now: day.addingTimeInterval(10 * 3_600), in: context)
        #expect(context.safeSave())

        let records = AttendanceEmailLog.dayRecords(on: day, in: context)
        #expect(records.latestSend == AttendanceEmailLog.latestSend(on: day, in: context))
        #expect(records.daySends == AttendanceEmailLog.daySends(on: day, in: context))
        #expect(records.daySends?.again != nil, "sent twice by email")
        #expect(records.isNotExpected == AttendanceEmailLog.isNotExpected(on: day, in: context))
        #expect(records.isNotExpected)
    }

    // MARK: - #21: Leave, and one session per site

    @Test("Leave drops what ParentLocker owed for the class, and keeps the sign-in (#21)")
    func leaveDropsWhatsOwed() {
        let device = FD1103Device(arrivalClosed: false)
        device.sync.closeArrivalSend(on: device.clock.now)
        #expect(device.unsent.load()?.wholeClass == true)
        #expect(device.sync.arrivalClosedHere)

        device.sync.classLeft()

        #expect(device.unsent.load() == nil)
        #expect(device.sync.wholeClass == nil)
        #expect(!device.sync.arrivalClosedHere)
        #expect(device.sync.undoEndsAt == nil)
        #expect(device.sync.isSignedIn, "the sign-in is hers, not the class's")
    }

    @Test("A sync's runs share one connection session per site (#21)")
    func oneSessionPerSite() throws {
        let make = ParentLockerSync.siteTransports()
        let first = try #require(make("school.parentlocker.test", [], { _ in }) as? ParentLockerHTTP)
        let second = try #require(make("https://School.ParentLocker.test/", [], { _ in }) as? ParentLockerHTTP)
        let other = try #require(make("other.parentlocker.test", [], { _ in }) as? ParentLockerHTTP)
        #expect(first.session === second.session)
        #expect(first.session !== other.session)
        let another = try #require(
            ParentLockerSync.siteTransports()("school.parentlocker.test", [], { _ in }) as? ParentLockerHTTP
        )
        #expect(another.session !== first.session, "another sync has its own")
    }
}
