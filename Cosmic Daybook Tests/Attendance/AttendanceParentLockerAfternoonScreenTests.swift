import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The notebook's attendance screens with ParentLocker picked, as the
/// afternoon bug hunt found them (report "ParentLocker bug hunt 2026-10-13
/// afternoon", M1–M4, M7, L6): the sign-in after Close Arrival & Send's Undo,
/// the iPhone row's Send and the reminder's tap, problems with no line, the
/// question before sending with children unmarked, Match Names after the
/// class went, and Send with no sign-in. Over the fake site, clock and keychain.
@Suite("Attendance screen and ParentLocker, afternoon fixes")
@MainActor
struct AttendanceParentLockerAfternoonScreenTests {

    typealias Device = ParentLockerTestDevice
    typealias Screen = AttendanceExpandedView

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    // MARK: - M1: the sign-in waits for the Undo

    @Test("Close Arrival & Send asks to sign in only once its Undo has gone")
    func signInWaitsForTheUndo() throws {
        let device = Device(site: site, clock: clock, secrets: FakeParentLockerSecrets(password: nil, cookie: nil),
                            arrivalClosed: false)
        #expect(device.sync.needsSignIn)
        device.sync.closeArrivalSend(on: Device.morning, after: 7)
        let undoEnds = try #require(device.sync.undoEndsAt)

        #expect(Screen.signInDelay(after: device.sync) == 7, "not over the Undo toast")
        clock.advance(by: 7)
        #expect(Screen.signInDelay(after: device.sync) == 0)
        #expect(Screen.asksToSignIn(afterUndoEnding: undoEnds, sync: device.sync))
    }

    @Test("Undo inside the window means no sign-in afterwards")
    func undoMeansNoSignIn() throws {
        let device = Device(site: site, clock: clock, secrets: FakeParentLockerSecrets(password: nil, cookie: nil),
                            arrivalClosed: false)
        device.sync.closeArrivalSend(on: Device.morning, after: 7)
        let undoEnds = try #require(device.sync.undoEndsAt)
        clock.advance(by: 3)
        device.sync.cancelCloseArrivalSend()
        clock.advance(by: 4)
        #expect(!Screen.asksToSignIn(afterUndoEnding: undoEnds, sync: device.sync))
        #expect(Screen.signInDelay(after: device.sync) == nil)
    }

    @Test("A signed-in device never asks")
    func signedInNeverAsks() {
        let device = Device(site: site, clock: clock, arrivalClosed: false)
        device.sync.closeArrivalSend(on: Device.morning, after: 7)
        #expect(Screen.signInDelay(after: device.sync) == nil)
    }

    // MARK: - M2: Send on the iPhone's row, and the reminder's tap

    @Test("The iPhone's row offers Send once everyone's marked and nothing has gone")
    func compactRowOffersSend() {
        #expect(Screen.compactRowOffersSend(isOpen: true, isFuture: false, isRollComplete: true))
        #expect(!Screen.compactRowOffersSend(isOpen: true, isFuture: false, isRollComplete: false))
        #expect(!Screen.compactRowOffersSend(isOpen: false, isFuture: false, isRollComplete: true), "already sent")
        #expect(!Screen.compactRowOffersSend(isOpen: true, isFuture: true, isRollComplete: true))
    }

    @Test("The reminder's tap offers ParentLocker's send with ParentLocker picked")
    func reminderTapOffersParentLocker() {
        #expect(Screen.reminderTap(sendsToParentLocker: true, parentLockerIsOpen: true, emailIsOpen: false)
            == .offerParentLocker)
        #expect(Screen.reminderTap(sendsToParentLocker: true, parentLockerIsOpen: false, emailIsOpen: false)
            == .nothing, "already sent")
        #expect(Screen.reminderTap(sendsToParentLocker: false, parentLockerIsOpen: false, emailIsOpen: true)
            == .openEmail)
        #expect(Screen.reminderTap(sendsToParentLocker: false, parentLockerIsOpen: false, emailIsOpen: false)
            == .nothing)

        let day = Device.morning
        let ready = ParentLockerSendQuestion.fromReminder(on: day, unmarked: [])
        #expect(ready.title == "Send today's attendance to ParentLocker?")
        #expect(ready.sendTitle == "Send")
        #expect(ready.day == day)
        let waiting = ParentLockerSendQuestion.fromReminder(on: day, unmarked: ["Maya S"])
        #expect(waiting.title == "1 child isn't marked yet")
        #expect(waiting.message.contains("Maya S"))
    }

    @Test("The due time comes from the shared row, 9:00 before there is one")
    func deadlineComesFromTheSharedRow() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        #expect(Screen.deadlineMinutes(in: ctx) == AttendanceEmailLog.defaultDeadlineMinutes)
        let settings = AttendanceEmailLog.Settings(
            isEnabled: false, toAddresses: "", nameOrder: .firstLast, groupByLevel: false,
            deadlineMinutes: 8 * 60 + 30, sendMethod: .parentLocker
        )
        #expect(AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: ctx))
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(Screen.deadlineMinutes(in: ctx) == 8 * 60 + 30)
    }

    // MARK: - M3: problems with no line

    @Test("A child's problem shows even when there's no line above it")
    func problemsShowWithoutALine() {
        let found = "None of the class's children were found in ParentLocker."
        let idle = ParentLockerStatus(state: .idle, problems: [found])
        #expect(idle.line(sentSummary: nil) == nil)
        #expect(ParentLockerStatusLine.content(for: idle, sentSummary: nil, showsProblems: true)
            == .init(line: nil, problems: [found]))
        #expect(ParentLockerStatusLine.content(for: idle, sentSummary: nil, showsProblems: false) == nil,
                "a compact row leaves the per-child lines out")
        #expect(ParentLockerStatusLine.content(for: ParentLockerStatus(), sentSummary: nil, showsProblems: true)
            == nil)
        #expect(ParentLockerStatusLine.content(
            for: ParentLockerStatus(state: .upToDate), sentSummary: "Sent to ParentLocker 8:47 AM by you",
            showsProblems: true
        ) == .init(line: "Sent to ParentLocker 8:47 AM by you · up to date", problems: []))
    }

    @Test("Send Now's toast gives the first problem when the run ends with nothing to say")
    func sendNowToastsTheFirstProblem() {
        let idle = ParentLockerStatus(state: .idle, problems: ["None found.", "Another."])
        #expect(Screen.sendNowToast(for: idle) == .error("None found."))
        #expect(Screen.sendNowToast(for: ParentLockerStatus(state: .idle)) == nil)
        #expect(Screen.sendNowToast(for: ParentLockerStatus(state: .upToDate)) == .success("Sent to ParentLocker"))
        let retrying = ParentLockerStatus(state: .retrying)
        #expect(Screen.sendNowToast(for: retrying) == retrying.message.map(Screen.SendNowToast.error))
    }

    // MARK: - M4: asking first, naming who isn't marked

    @Test("Send Now asks first while anyone is unmarked, and names them")
    func sendNowAsksAndNames() throws {
        let day = Device.morning
        #expect(ParentLockerSendQuestion.beforeSending(on: day, unmarked: []) == nil, "everyone's marked: it sends")

        let three = try #require(ParentLockerSendQuestion.beforeSending(
            on: day, unmarked: ["Maya S", "Wren H", "June A"]
        ))
        #expect(three.title == "3 children aren't marked yet")
        for name in ["Maya S", "Wren H", "June A"] { #expect(three.message.contains(name)) }
        #expect(three.sendTitle == "Send the Rest")
        #expect(three.day == day)

        let one = try #require(ParentLockerSendQuestion.beforeSending(on: day, unmarked: ["Maya S"]))
        #expect(one.title == "1 child isn't marked yet")
    }

    @Test("The Shortcut asks with the count before sending the rest")
    func shortcutAsksWithTheCount() {
        #expect(SendAttendanceIntent.unmarkedQuestion(count: 0) == nil)
        #expect(SendAttendanceIntent.unmarkedQuestion(count: 1) == "1 child isn't marked yet. Send the rest?")
        #expect(SendAttendanceIntent.unmarkedQuestion(count: 3) == "3 children aren't marked yet. Send the rest?")
    }

    // MARK: - M7: Match Names after the class went

    @Test("A child matched after the class went is sent as this device's change")
    func matchAfterTheClassWentIsSent() async {
        let device = Device(site: site, clock: clock, sent: true, marks: [Device.marisol: Device.mark(.present)])
        #expect(device.store.writeMatches([Device.marisol: "40003"]))
        ParentLockerMatchView.notePick(of: Device.marisol, displacing: Device.wren, in: device.sync)
        #expect(Set(device.sync.localChanges.keys) == [Device.marisol, Device.wren])

        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(site.mark(40003) == "701", "Marisol is Present in ParentLocker")
    }

    @Test("A match made before the class went waits for the whole-class send")
    func matchBeforeTheClassWentWaits() {
        let device = Device(site: site, clock: clock, arrivalClosed: false)
        ParentLockerMatchView.notePick(of: Device.marisol, displacing: nil, in: device.sync)
        #expect(device.sync.localChanges.isEmpty)
    }

    @Test("A pick displaces whoever held that ParentLocker child, never the picked child itself")
    func pickDisplacesTheHolder() {
        typealias Row = ParentLockerMatchView.Row
        let rows = [
            Row(id: Device.wren, name: "Wren H", studentID: "40001", needsYou: false),
            Row(id: Device.june, name: "June A", studentID: nil, needsYou: true),
            Row(id: Device.bea, name: "Bea M", studentID: ParentLockerPlanner.notMatchedID, needsYou: false)
        ]
        #expect(ParentLockerMatchView.displaced(by: "40001", picking: Device.june, in: rows) == Device.wren)
        #expect(ParentLockerMatchView.displaced(by: "40001", picking: Device.wren, in: rows) == nil)
        #expect(ParentLockerMatchView.displaced(by: "40002", picking: Device.june, in: rows) == nil)
        #expect(ParentLockerMatchView.displaced(
            by: ParentLockerPlanner.notMatchedID, picking: Device.june, in: rows
        ) == nil, "leaving a child out takes nobody's match")
    }

    // MARK: - L6: one tap without a sign-in

    @Test("Send with no sign-in opens the sheet, and for today also asks the sync to send")
    func sendWithoutSignInIsOneTap() {
        #expect(Screen.sendSteps(needsSignIn: true, isToday: true) == (sends: true, opensSignIn: true))
        #expect(Screen.sendSteps(needsSignIn: true, isToday: false) == (sends: false, opensSignIn: true),
                "another day waits for a tap after signing in")
        #expect(Screen.sendSteps(needsSignIn: false, isToday: true) == (sends: true, opensSignIn: false))
        #expect(Screen.sendSteps(needsSignIn: false, isToday: false) == (sends: true, opensSignIn: false))
    }
}
