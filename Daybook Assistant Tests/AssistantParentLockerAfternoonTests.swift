import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The Assistant's and Siri's side of the ParentLocker bug hunt of
// 2026-10-13 (afternoon): H2, M2, M4, L1, L2, L4, L5 and L6.
@Suite("Assistant ParentLocker afternoon fixes")
@MainActor
struct AssistantParentLockerAfternoonTests {

    private let today = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - H2: Siri's Undo of a Close Arrival stops the send

    @Test("H2: Siri's Undo of a Close Arrival stops the running sync's send")
    func undoStopsTheRunningSend() {
        let sync = FakeParentLockerSender(isSignedIn: false)
        let unsent = ParentLockerMemoryUnsentStore(ParentLockerUnsent(
            day: AppCalendar.dayID(today), children: [], wholeClass: true, arrivalClosed: true
        ))
        AssistantSiriCommands.undoCloseSend(on: today, sync: sync, unsent: unsent)
        #expect(sync.cancels == 1)
        #expect(unsent.load()?.wholeClass == true, "the running sync keeps its own owed send")
    }

    @Test("H2: with no sync running, Siri's Undo takes back the send kept for launch and its closed arrival")
    func undoClearsTheOwedSend() throws {
        let child = UUID()
        let unsent = ParentLockerMemoryUnsentStore(ParentLockerUnsent(
            day: AppCalendar.dayID(today), children: [child], wholeClass: true, arrivalClosed: true
        ))
        AssistantSiriCommands.undoCloseSend(on: today, sync: nil, unsent: unsent)
        let owed = try #require(unsent.load(), "a child's own change stays owed")
        #expect(!owed.wholeClass)
        #expect(!owed.arrivalClosed)
        #expect(owed.children == [child])

        let alone = ParentLockerMemoryUnsentStore(ParentLockerUnsent(
            day: AppCalendar.dayID(today), children: [], wholeClass: true, arrivalClosed: true
        ))
        AssistantSiriCommands.undoCloseSend(on: today, sync: nil, unsent: alone)
        #expect(alone.load() == nil)
    }

    @Test("H2: Siri's Undo leaves another day's owed send alone")
    func undoLeavesAnotherDay() {
        let yesterday = AppCalendar.addingDays(-1, to: today)
        let owed = ParentLockerUnsent(
            day: AppCalendar.dayID(yesterday), children: [], wholeClass: true, arrivalClosed: true
        )
        let unsent = ParentLockerMemoryUnsentStore(owed)
        AssistantSiriCommands.undoCloseSend(on: today, sync: nil, unsent: unsent)
        #expect(unsent.load() == owed)
    }

    @Test("H2: what Siri says when ParentLocker already has the class is plain")
    func keepsAbsencesWordsArePlain() {
        let line = SiriAttendanceChange.parentLockerKeepsAbsences
        #expect(line.contains("ParentLocker"))
        for word in ["http", ".com", "error", "server", "request", "sync"] {
            #expect(!line.lowercased().contains(word), "says \(word)")
        }
    }

    // MARK: - L5: a refused password is not signed in

    @Test("L5: Siri's Close Arrival with a refused password gives the not-signed-in reply and waits for the sign-in")
    func refusedPasswordIsNotSignedIn() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        #expect(context.safeSave())
        ParentLockerTestSettings.pick(.parentLocker, in: context)
        let siri = SiriAttendance(stack: stack, role: .assistant, today: today)
        let sync = FakeParentLockerSender(isSignedIn: true, passwordRefused: true)
        #expect(await AssistantSiriCommands.sendAfterClose(siri, sync: sync) == .notSignedIn)
        #expect(sync.sentDays.isEmpty, "a refused password is never tried again by itself")
        #expect(sync.closedDays == [siri.today])
    }

    // MARK: - M4 and L6: Send Now

    @Test("M4: Send Now with children unmarked asks first and names them")
    func sendNowAsksAboutTheUnmarked() {
        let sync = FakeParentLockerSender(unmarked: ["Ari", "Maya"])
        #expect(AssistantParentLockerSendStep.first(on: today, isToday: true, unmarkedConfirmed: false, sync: sync)
            == .ask(unmarked: ["Ari", "Maya"]))
        #expect(AssistantParentLockerSendStep.first(on: today, isToday: true, unmarkedConfirmed: true, sync: sync)
            == .send)
        let marked = FakeParentLockerSender()
        #expect(AssistantParentLockerSendStep.first(on: today, isToday: true, unmarkedConfirmed: false, sync: marked)
            == .send)
    }

    @Test("M4: the question names the children and says the day isn't finished")
    func sendNowQuestionWords() {
        #expect(AssistantParentLockerSendStep.question(unmarked: ["Ari"]) == "Ari isn't marked yet")
        #expect(AssistantParentLockerSendStep.question(unmarked: ["Ari", "Maya", "Sam"])
            == "3 children aren't marked yet")
        #expect(AssistantParentLockerSendStep.questionMessage(unmarked: ["Ari", "Maya"])
            == "Ari and Maya aren't marked. Everyone else goes to ParentLocker now. "
                + "Mark them and send again to finish the day.")
    }

    @Test("L6: Send while not signed in sends today once she signs in, and opens the sign-in in one tap")
    func sendWhileSignedOut() {
        let signedOut = FakeParentLockerSender(isSignedIn: false)
        #expect(AssistantParentLockerSendStep.first(on: today, isToday: true, unmarkedConfirmed: false, sync: signedOut)
            == .sendAfterSignIn)
        #expect(AssistantParentLockerSendStep.first(
            on: today, isToday: false, unmarkedConfirmed: false, sync: signedOut
        ) == .signIn, "a send waiting for a sign-in is for today only")
        let refused = FakeParentLockerSender(isSignedIn: true, passwordRefused: true)
        #expect(AssistantParentLockerSendStep.first(on: today, isToday: true, unmarkedConfirmed: false, sync: refused)
            == .sendAfterSignIn)
        // Unmarked children are asked about first, signed in or not.
        let both = FakeParentLockerSender(isSignedIn: false, unmarked: ["Ari"])
        #expect(AssistantParentLockerSendStep.first(on: today, isToday: true, unmarkedConfirmed: false, sync: both)
            == .ask(unmarked: ["Ari"]))
        #expect(AssistantParentLockerSendStep.first(on: today, isToday: true, unmarkedConfirmed: true, sync: both)
            == .sendAfterSignIn)
    }

    // MARK: - L1: a past day's Send Now says how it went

    @Test("L1: a past day's Send Now that fails says why")
    func pastDayFailureIsShown() {
        typealias Row = AssistantParentLockerRow
        #expect(Row.pastDayMessage(after: ParentLockerStatus(state: .retrying))
            == ParentLockerStatus(state: .retrying).message)
        #expect(Row.pastDayMessage(after: ParentLockerStatus(state: .signedOut))
            == ParentLockerStatus(state: .signedOut).message)
        #expect(Row.pastDayMessage(after: ParentLockerStatus(state: .pageChanged)) != nil)
        #expect(Row.pastDayMessage(after: ParentLockerStatus(state: .upToDate)) == nil, "the line shows the send")
        let noneFound = "None of the class's children were found in ParentLocker."
        #expect(Row.pastDayMessage(after: ParentLockerStatus(state: .idle, problems: [noneFound])) == noneFound)
    }

    // MARK: - L2: the sign-in follows the waiting send, not the Undo

    @Test("L2: the sign-in opens for a send waiting on it, after the Undo's moment, even with the Undo gone")
    func signInFollowsTheWaitingSend() {
        typealias Bar = AssistantArrivalBar
        let undoEnds = today.addingTimeInterval(7)
        #expect(Bar.signInPrompt(awaitsSignIn: true, needsSignIn: true, undoEndsAt: undoEnds, asked: false, now: today)
            == .at(undoEnds), "never over the Undo")
        #expect(Bar.signInPrompt(
            awaitsSignIn: true, needsSignIn: true, undoEndsAt: undoEnds, asked: false, now: undoEnds
        ) == .now)
        // Locked during the Undo: the Undo went, the waiting send didn't.
        #expect(Bar.signInPrompt(awaitsSignIn: true, needsSignIn: true, undoEndsAt: nil, asked: false, now: today)
            == .now)
        #expect(Bar.signInPrompt(awaitsSignIn: true, needsSignIn: true, undoEndsAt: nil, asked: true, now: today)
            == .none, "closed without signing in: not again for this send")
        #expect(Bar.signInPrompt(awaitsSignIn: false, needsSignIn: true, undoEndsAt: nil, asked: false, now: today)
            == .none, "nothing waits")
        #expect(Bar.signInPrompt(awaitsSignIn: true, needsSignIn: false, undoEndsAt: nil, asked: false, now: today)
            == .none, "signed in")
    }

    // MARK: - L4: the Classroom row after a refused password

    @Test("L4: the Classroom row says Sign in again after a refused password")
    func classroomRowAfterRefusal() {
        typealias Section = AssistantParentLockerSection
        #expect(Section.signInLabel(isSignedIn: true, needsSignIn: false) == "Signed in")
        #expect(Section.signInLabel(isSignedIn: true, needsSignIn: true) == "Sign in again")
        #expect(Section.signInLabel(isSignedIn: false, needsSignIn: true) == "Not signed in")
    }

    // MARK: - M2: everyone's marked, so Send is what's offered

    @Test("M2: with everyone marked and nothing sent, the line offers Send rather than waiting for arrival")
    func everyoneMarkedOffersSend() {
        typealias Row = AssistantParentLockerRow
        let waiting = ParentLockerStatus(state: .waitingForArrival)
        #expect(!Row.showsStatusMenu(offersSend: true, status: waiting, sentSummary: nil),
                "no 'when arrival closes' beside Send")
        #expect(Row.showsStatusMenu(offersSend: false, status: waiting, sentSummary: nil))
        #expect(Row.showsStatusMenu(offersSend: true, status: ParentLockerStatus(state: .signedOut), sentSummary: nil))
        #expect(Row.showsStatusMenu(
            offersSend: true, status: ParentLockerStatus(state: .waitingForArrival, problems: ["Ari is locked"]),
            sentSummary: nil
        ), "a problem still shows")
    }
}

// MARK: - H2: what Siri says

// In `AssistantSiriTests`, so they run one at a time with it: closing
// arrival writes the app's own Late and Siri memories.
extension AssistantSiriTests {

    private static let afternoonMonday = "2031-01-06"

    @Test("H2: Siri's Undo of a Close Arrival the class has already gone with says ParentLocker keeps the absences")
    func siriUndoAfterTheClassWent() async throws {
        let day = try AssistantTestSupport.day(Self.afternoonMonday)
        defer {
            SiriAttendanceChange.forget()
            AttendanceLatePhase.setLate(false, on: day)
        }
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        #expect(context.safeSave())
        ParentLockerTestSettings.pick(.parentLocker, in: context)
        let siri = SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))

        #expect(try await AssistantSiriCommands.closeArrival(siri) == 2)
        #expect(try await siri.undoLast() == "Done. Arrival is open again.", "nothing went yet: nothing to say")

        #expect(try await AssistantSiriCommands.closeArrival(siri) == 2)
        AttendanceEmailLog.recordSend(on: siri.today, role: .assistant, channel: .parentLocker, in: context)
        #expect(context.safeSave())
        #expect(try await siri.undoLast()
            == "Done. Arrival is open again. " + SiriAttendanceChange.parentLockerKeepsAbsences)
    }

    @Test("H2: an email sent for the day says nothing about ParentLocker")
    func siriUndoAfterAnEmail() async throws {
        let day = try AssistantTestSupport.day(Self.afternoonMonday)
        defer {
            SiriAttendanceChange.forget()
            AttendanceLatePhase.setLate(false, on: day)
        }
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        #expect(context.safeSave())
        let siri = SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 1)
        AttendanceEmailLog.recordSend(on: siri.today, role: .assistant, in: context)
        #expect(context.safeSave())
        #expect(try await siri.undoLast() == "Done. Arrival is open again.")
    }
}
