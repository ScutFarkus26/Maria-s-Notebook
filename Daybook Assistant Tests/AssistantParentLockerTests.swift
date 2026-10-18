import Foundation
import CoreData
import Testing
import UserNotifications
@testable import Daybook_Assistant

/// Stands in for the class's ParentLocker sync: signed in or not (or with a
/// password ParentLocker refused), the children it finds unmarked, and the
/// status a Send Now ends on. Remembers each day it was asked to send, each
/// Close Arrival & Send left waiting, with its Undo window, and each Undo.
@MainActor
final class FakeParentLockerSender: AssistantParentLockerSending {
    var isSignedIn: Bool
    var passwordRefused: Bool
    var needsSignIn: Bool { !isSignedIn || passwordRefused }
    var awaitsSignIn = false
    var endsOn: ParentLockerStatus.State
    var unmarked: [String]
    private(set) var sentDays: [Date] = []
    private(set) var closedDays: [Date] = []
    private(set) var undoWindows: [TimeInterval] = []
    private(set) var cancels = 0

    init(
        isSignedIn: Bool = true, passwordRefused: Bool = false,
        endsOn: ParentLockerStatus.State = .upToDate, unmarked: [String] = []
    ) {
        self.isSignedIn = isSignedIn
        self.passwordRefused = passwordRefused
        self.endsOn = endsOn
        self.unmarked = unmarked
    }

    func unmarkedNames(on day: Date) -> [String] { unmarked }

    func cancelCloseArrivalSend() { cancels += 1 }

    func sendNow(day: Date) async -> ParentLockerStatus {
        sentDays.append(day)
        return ParentLockerStatus(state: endsOn)
    }

    func closeArrivalSend(on day: Date, after undoWindow: TimeInterval) {
        closedDays.append(day)
        undoWindows.append(undoWindow)
    }

    /// Siri's Close Arrival & Send, signed in: a send of the day.
    func closeArrivalSendNow(on day: Date) async -> ParentLockerStatus {
        sentDays.append(day)
        return ParentLockerStatus(state: endsOn)
    }
}

/// The guide's settings in the share, as the notebook writes them.
@MainActor
enum ParentLockerTestSettings {
    static func pick(_ method: AttendanceSendMethod, in context: NSManagedObjectContext) {
        let settings = AttendanceEmailLog.Settings(
            isEnabled: method == .email,
            toAddresses: method == .email ? "office@example.com" : "",
            nameOrder: .firstLast,
            groupByLevel: false,
            sendMethod: method
        )
        AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: context)
        _ = context.safeSave()
    }
}

// The Assistant's ParentLocker screens (plan "ParentLocker attendance",
// Phase 4): with ParentLocker picked the email steps aside, Close Arrival
// sends today, and everyone marked with nothing sent offers the send.
@Suite("Assistant ParentLocker")
@MainActor
struct AssistantParentLockerTests {

    /// The school day these tests take for today, whatever day they run: on
    /// a weekend the real today is a day off, which offers nothing.
    private static func monday() throws -> Date { try AssistantTestSupport.day("2026-10-12") }

    /// A class of two, Ari and Maya, on `day` (the Monday when nil), with
    /// `method` picked, seen at nine on the Monday.
    private func classOfTwo(
        _ method: AttendanceSendMethod?, on day: Date? = nil
    ) throws -> (CoreDataStack, AssistantAttendanceViewModel) {
        let monday = try Self.monday()
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        #expect(context.safeSave())
        if let method { ParentLockerTestSettings.pick(method, in: context) }
        let viewModel = AssistantTestSupport.viewModel(
            stack, on: day ?? monday, now: monday.addingTimeInterval(9 * 3_600)
        )
        return (stack, viewModel)
    }

    @Test("With ParentLocker picked, the email isn't offered and today's Close Arrival sends")
    func parentLockerReplacesTheEmail() throws {
        let (_, viewModel) = try classOfTwo(.parentLocker)
        let frontDesk = viewModel.frontDesk
        #expect(viewModel.isToday)
        #expect(frontDesk.sendsToParentLocker)
        #expect(!frontDesk.isOffered(by: viewModel))
        #expect(frontDesk.offersParentLocker(by: viewModel))
        #expect(!frontDesk.offersCloseAndEmail(by: viewModel))
        #expect(frontDesk.closesWithSend(by: viewModel, hasSync: true))
        // The Sample Class runs no sync: a plain Close Arrival there.
        #expect(!frontDesk.closesWithSend(by: viewModel, hasSync: false))
        #expect(frontDesk.draft(for: viewModel.rows) == nil)
    }

    @Test("With email picked, nothing about ParentLocker shows")
    func emailStaysAsItWas() throws {
        let (_, viewModel) = try classOfTwo(.email)
        let frontDesk = viewModel.frontDesk
        #expect(!frontDesk.sendsToParentLocker)
        #expect(frontDesk.isOffered(by: viewModel))
        #expect(!frontDesk.offersParentLocker(by: viewModel))
        #expect(!frontDesk.offersParentLockerSend(by: viewModel))
        #expect(!frontDesk.closesWithSend(by: viewModel, hasSync: true))
    }

    @Test("Before the guide sets anything up, nothing is offered")
    func nothingSetUp() throws {
        let (_, viewModel) = try classOfTwo(nil)
        #expect(!viewModel.frontDesk.offersParentLocker(by: viewModel))
        #expect(!viewModel.frontDesk.closesWithSend(by: viewModel, hasSync: true))
    }

    @Test("Another day's Close Arrival doesn't send; that day goes by Send Now")
    func onlyTodaySendsOnClose() throws {
        let lastWeek = try #require(Calendar.current.date(byAdding: .day, value: -7, to: try Self.monday()))
        let (_, viewModel) = try classOfTwo(.parentLocker, on: lastWeek)
        #expect(!viewModel.isToday)
        #expect(!viewModel.frontDesk.closesWithSend(by: viewModel, hasSync: true))
    }

    @Test("Send to ParentLocker is offered once everyone's marked and nobody has sent the day")
    func sendOfferedWhenEveryoneIsMarked() throws {
        let (stack, viewModel) = try classOfTwo(.parentLocker)
        #expect(viewModel.unmarkedCount == 2)
        #expect(!viewModel.frontDesk.offersParentLockerSend(by: viewModel))

        for row in viewModel.rows { viewModel.tap(row) }
        viewModel.load()
        #expect(viewModel.unmarkedCount == 0)
        #expect(viewModel.frontDesk.offersParentLockerSend(by: viewModel))

        let send = AttendanceEmailLog.recordSend(
            on: viewModel.date, role: .assistant, channel: .parentLocker, in: stack.viewContext
        )
        #expect(AssistantSave.save(stack.viewContext, container: nil, created: [send]))
        viewModel.load()
        #expect(viewModel.frontDesk.latestSend?.channel == .parentLocker)
        #expect(!viewModel.frontDesk.offersParentLockerSend(by: viewModel))
    }

    @Test("The close question's button says it sends when it does")
    func closeButtonTitle() {
        #expect(AssistantArrivalBar.closeButtonTitle(unmarked: 3, sends: true) == "Mark 3 Absent & Send")
        #expect(AssistantArrivalBar.closeButtonTitle(unmarked: 1, sends: false) == "Mark 1 Absent")
    }

    @Test("A Close Arrival & Send's Undo is marked to stop the send")
    func undoCarriesTheSend() {
        #expect(!ArrivalUndo(count: 2).sendsToParentLocker)
        #expect(ArrivalUndo(count: 2, sendsToParentLocker: true).sendsToParentLocker)
    }

    @Test("The sign-in sheet's words are plain, and the password line says where it lives")
    func signInWordsArePlain() {
        typealias Sheet = ParentLockerSignInSheet
        let sheet = [Sheet.title, Sheet.onceLine, Sheet.noticeTitle]
        let lines = sheet + Sheet.notice.map(\.text)
            + [AssistantParentLockerSection.signedInFooter, AssistantParentLockerSection.signedOutFooter,
               AssistantParentLockerRow.notSentLine]
        for line in lines {
            for word in ["http", "cookie", "error", "server", "request", "token", "session"] {
                #expect(!line.lowercased().contains(word), "\(line) says \(word)")
            }
        }
        #expect(ParentLockerSignInSheet.notice.contains {
            $0.text == "Your password is saved in your iCloud Keychain, which Apple encrypts. "
                + "Only your own devices can read it. It's never stored in the app or its backups, "
                + "and none of your co-workers can see it or use it."
        })
    }

    @Test("With ParentLocker picked, the reminder's permission is asked as for the email")
    func reminderPermissionFollowsParentLocker() async throws {
        let defaults = UserDefaults.standard
        let key = FrontDeskEmailReminder.enabledKey
        let before = defaults.object(forKey: key)
        defaults.set(true, forKey: key)
        defer { defaults.set(before, forKey: key) }

        func requests(_ method: AttendanceSendMethod?) async throws -> Int {
            let (stack, _) = try classOfTwo(method)
            let center = FakeReminderCenter()
            center.status = .notDetermined
            await ArrivalReminderFollower.askPermission(
                in: stack.viewContext, setupDone: true, isSample: false, center: center
            )
            return center.authorizationRequests
        }
        let withNothing = try await requests(nil)
        #expect(try await requests(.parentLocker) == withNothing + 1)
        #expect(try await requests(.email) == withNothing + 1)
    }
}

// MARK: - Siri's Close Arrival

// In `AssistantSiriTests`, so they run one at a time with it: closing
// arrival writes the app's own Late and Siri memories.
extension AssistantSiriTests {

    private static let parentLockerMonday = "2031-01-06"

    private static func closedClass(
        _ method: AttendanceSendMethod
    ) async throws -> (SiriAttendance, Date) {
        let day = try AssistantTestSupport.day(Self.parentLockerMonday)
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Ari", "Cedar", in: context)
        AssistantTestSupport.student("Maya", "Stone", in: context)
        #expect(context.safeSave())
        ParentLockerTestSettings.pick(method, in: context)
        let siri = SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 2)
        return (siri, day)
    }

    private static func forgetClose(on day: Date) {
        SiriAttendanceChange.forget()
        AttendanceLatePhase.setLate(false, on: day)
    }

    @Test("Siri's Close Arrival sends the class when ParentLocker is picked and the iPhone is signed in")
    func siriCloseArrivalSends() async throws {
        let (siri, day) = try await Self.closedClass(.parentLocker)
        defer { Self.forgetClose(on: day) }
        let sync = FakeParentLockerSender()
        let outcome = await AssistantSiriCommands.sendAfterClose(siri, sync: sync)
        #expect(outcome == .sent)
        #expect(sync.sentDays == [siri.today])
        #expect(AssistantSiriCommands.closedDialog(marked: 2, parentLocker: outcome)
            == "Arrival is closed. 2 children are marked absent. Attendance went to ParentLocker.")
    }

    @Test("Siri's Close Arrival says plainly it couldn't send when the iPhone isn't signed in")
    func siriCloseArrivalNotSignedIn() async throws {
        let (siri, day) = try await Self.closedClass(.parentLocker)
        defer { Self.forgetClose(on: day) }
        let sync = FakeParentLockerSender(isSignedIn: false)
        let outcome = await AssistantSiriCommands.sendAfterClose(siri, sync: sync)
        #expect(outcome == .notSignedIn)
        #expect(sync.sentDays.isEmpty)
        #expect(AssistantSiriCommands.closedDialog(marked: 2, parentLocker: outcome)
            == "Arrival is closed. 2 children are marked absent. Attendance hasn't gone to ParentLocker yet. "
                + "Open the Assistant and sign in to ParentLocker to send it.")
    }

    @Test("Siri's Close Arrival on an iPhone not signed in leaves the class waiting to send once she signs in")
    func siriCloseArrivalWaitsForSignIn() async throws {
        let (siri, day) = try await Self.closedClass(.parentLocker)
        defer { Self.forgetClose(on: day) }
        let sync = FakeParentLockerSender(isSignedIn: false)
        #expect(await AssistantSiriCommands.sendAfterClose(siri, sync: sync) == .notSignedIn)
        #expect(sync.closedDays == [siri.today])
        #expect(sync.undoWindows == [0], "Siri offers no Undo")
        #expect(sync.sentDays.isEmpty)
    }

    @Test("Siri's Close Arrival with the class's sync not running keeps the send for it to make at launch")
    func siriCloseArrivalOwedForLaunch() async throws {
        let (siri, day) = try await Self.closedClass(.parentLocker)
        defer { Self.forgetClose(on: day) }
        let unsent = ParentLockerMemoryUnsentStore(ParentLockerUnsent(
            day: AppCalendar.dayID(siri.today), children: [UUID()], wholeClass: false
        ))
        #expect(await AssistantSiriCommands.sendAfterClose(siri, sync: nil, unsent: unsent) == .notSentYet)
        let owed = try #require(unsent.load())
        #expect(owed.day == AppCalendar.dayID(siri.today))
        #expect(owed.wholeClass)
        #expect(owed.arrivalClosed)
        #expect(owed.children.count == 1, "what was owed before stays owed")
    }

    @Test("Siri's Close Arrival sends while the join screen's sample is open: Siri marks the real class")
    func siriCloseArrivalUnderTheSample() async throws {
        let (siri, day) = try await Self.closedClass(.parentLocker)
        let wasChosen = AssistantSampleClass.isChosen
        AssistantSampleClass.isChosen = true
        defer {
            AssistantSampleClass.isChosen = wasChosen
            Self.forgetClose(on: day)
        }
        let sync = FakeParentLockerSender()
        #expect(await AssistantSiriCommands.sendAfterClose(siri, sync: sync) == .sent)
        #expect(sync.sentDays == [siri.today])
    }

    @Test("Siri's Close Arrival says it couldn't send yet when ParentLocker can't be reached or the sync isn't running")
    func siriCloseArrivalNotSentYet() async throws {
        let (siri, day) = try await Self.closedClass(.parentLocker)
        defer { Self.forgetClose(on: day) }
        for state in [ParentLockerStatus.State.retrying, .notSentYet, .passwordRefused, .pageChanged] {
            let outcome = await AssistantSiriCommands.sendAfterClose(siri, sync: FakeParentLockerSender(endsOn: state))
            #expect(outcome == .notSentYet, "after \(state)")
        }
        #expect(await AssistantSiriCommands.sendAfterClose(siri, sync: nil) == .notSentYet)
        #expect(await AssistantSiriCommands.sendAfterClose(siri, sync: FakeParentLockerSender(endsOn: .previewed))
            == .previewed)
        #expect(AssistantSiriCommands.closedDialog(marked: 1, parentLocker: .notSentYet)
            == "Arrival is closed. 1 child is marked absent. Attendance hasn't gone to ParentLocker yet. "
                + "Open the Assistant to send it.")
    }

    @Test("With email picked, Siri's Close Arrival says what it always did and sends nothing")
    func siriCloseArrivalByEmail() async throws {
        let (siri, day) = try await Self.closedClass(.email)
        defer { Self.forgetClose(on: day) }
        let sync = FakeParentLockerSender()
        let outcome = await AssistantSiriCommands.sendAfterClose(siri, sync: sync)
        #expect(outcome == .notPicked)
        #expect(sync.sentDays.isEmpty)
        #expect(AssistantSiriCommands.closedDialog(marked: 2, parentLocker: outcome)
            == "Arrival is closed. 2 children are marked absent.")
        #expect(AssistantSiriCommands.closedDialog(marked: 0, parentLocker: outcome)
            == "Arrival is closed. Everyone was already marked.")
    }

    @Test("Nothing Siri says about ParentLocker carries a web address or technical words")
    func siriParentLockerWordsArePlain() {
        let outcomes: [AssistantParentLockerAfterClose] = [
            .notPicked, .sent, .previewed, .notSignedIn, .notSentYet, .notExpected
        ]
        for outcome in outcomes {
            let text = AssistantSiriCommands.closedDialog(marked: 3, parentLocker: outcome).lowercased()
            for word in ["http", ".com", "cookie", "error", "keychain", "server", "request"] {
                #expect(!text.contains(word), "\(outcome) says \(word)")
            }
        }
    }
}
