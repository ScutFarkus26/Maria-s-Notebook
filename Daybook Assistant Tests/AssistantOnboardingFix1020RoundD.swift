import Foundation
import CoreData
import Testing
import UserNotifications
@testable import Daybook_Assistant

// Review (d) of the 2026-10-20 onboarding fixes: Not Now still led to the
// notification question through early pickups, and turned the front-desk
// reminder off for good; two name sheets could still be asked for at once
// (an Apple Account change during setup, and the attendance screen's own),
// and a saved name was set only after the sheet went, so it could show
// again; a relaunch went back to Welcome; and the refusal named the app by
// a name Settings doesn't use.
@Suite("Assistant onboarding fixes 2026-10-20, review (d)")
@MainActor
struct AssistantOnboardingFix1020RoundD {

    private let defaults = AssistantTestSupport.makeDefaults()

    // MARK: - #1 Not Now asks nothing

    @Test("After Not Now, a pickup on the roll doesn't ask about notifications")
    func notNowAsksNothing() async throws {
        let context = try AssistantTestSupport.makeStack().viewContext
        try pickupTomorrow(in: context)
        AssistantSetupReminder.decline(defaults)
        let center = FakeReminderCenter()
        center.status = .notDetermined

        await ArrivalReminderFollower.askPermission(
            in: context, setupDone: true, isSample: false, center: center, defaults: defaults
        )

        #expect(center.authorizationRequests == 0)
    }

    @Test("Once she turns a reminder on herself, the question is asked again")
    func turningOnAsksAgain() async throws {
        let context = try AssistantTestSupport.makeStack().viewContext
        try pickupTomorrow(in: context)
        AssistantSetupReminder.decline(defaults)
        AssistantSetupReminder.turnedOn(.pickup, defaults: defaults)
        let center = FakeReminderCenter()
        center.status = .notDetermined

        await ArrivalReminderFollower.askPermission(
            in: context, setupDone: true, isSample: false, center: center, defaults: defaults
        )

        // The pickup's question, and any other reminder's that's on here.
        #expect(center.authorizationRequests > 0)
        #expect(!AssistantSetupReminder.declinedInSetup(defaults))
    }

    // MARK: - #6 The front-desk reminder comes back

    @Test("Turning the arrival reminder back on after Not Now brings the front-desk one back")
    func arrivalBringsFrontDeskBack() {
        AssistantSetupReminder.decline(defaults)
        defaults.set(true, forKey: ArrivalReminder.enabledKey)
        AssistantSetupReminder.turnedOn(.arrival, defaults: defaults)
        #expect(FrontDeskEmailReminder.isEnabled(defaults))
    }

    @Test("A front-desk reminder she turned off herself stays off when the arrival one goes on")
    func ownChoiceStays() {
        defaults.set(false, forKey: FrontDeskEmailReminder.enabledKey)
        AssistantSetupReminder.turnedOn(.arrival, defaults: defaults)
        #expect(!FrontDeskEmailReminder.isEnabled(defaults))
    }

    @Test("All Set's front-desk line: when it comes, Off, or Notifications off")
    func frontDeskLine() {
        #expect(AssistantSetupReminder.frontDeskSummary(
            on: true, leadMinutes: 10, dueAt: "9:00 AM", notificationsOff: false
        ) == "10 min before 9:00 AM")
        #expect(AssistantSetupReminder.frontDeskSummary(
            on: false, leadMinutes: 10, dueAt: "9:00 AM", notificationsOff: true
        ) == "Off")
        #expect(AssistantSetupReminder.frontDeskSummary(
            on: true, leadMinutes: 10, dueAt: "9:00 AM", notificationsOff: true
        ) == "Notifications off")
    }

    // MARK: - #7 Wording

    @Test("The refusal names no app name Settings doesn't show")
    func refusalWording() {
        #expect(AssistantSetupReminder.refusedLine == "Notifications are off for this app. Turn them on in Settings.")
    }

    // MARK: - #2, #8 One name sheet

    @Test("An Apple Account change during setup asks once, after setup, and only if setup didn't get her name")
    func accountChangeDuringSetup() {
        // Setup up: nothing else asks.
        #expect(!AssistantFirstRun.asksForName(
            setupShowing: true, setupDone: false, isSample: false, hasName: false))
        // Setup over without a name: the one sheet asks.
        #expect(AssistantFirstRun.asksForName(
            setupShowing: false, setupDone: true, isSample: false, hasName: false))
        // Setup over with her name: nothing to ask, whatever the account change said.
        #expect(!AssistantFirstRun.asksForName(
            setupShowing: false, setupDone: true, isSample: false, hasName: true))
    }

    @Test("A missing name after setup is asked by the same one sheet, never over the sample")
    func missingNameAfterSetup() {
        #expect(AssistantFirstRun.asksForName(
            setupShowing: false, setupDone: true, isSample: false, hasName: false))
        #expect(!AssistantFirstRun.asksForName(
            setupShowing: false, setupDone: true, isSample: true, hasName: false))
        // Before setup's cover is up, setup is what asks.
        #expect(!AssistantFirstRun.asksForName(
            setupShowing: false, setupDone: false, isSample: false, hasName: false))
    }

    // MARK: - #5 Relaunch

    @Test("A relaunch after reaching the invitation opens on it; a swap within the launch keeps the page")
    func relaunchPage() {
        typealias Page = AssistantOnboardingView.Page
        #expect(AssistantOnboardingView.startPage(restored: .welcome, introSeen: true, firstThisLaunch: true)
            == Page.invitation)
        #expect(AssistantOnboardingView.startPage(restored: .iCloud, introSeen: true, firstThisLaunch: false)
            == Page.iCloud)
        #expect(AssistantOnboardingView.startPage(restored: .practice, introSeen: false, firstThisLaunch: true)
            == Page.practice)
    }

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

extension AssistantIdentitySuites {

    // #4: the name sheet's Save set her name in a task and went at once, so
    // for a moment there was still no name and the sheet could come back.
    @Suite("Assistant name sheet saves before it goes, review (d)")
    @MainActor
    struct AssistantNameCommitRoundD {

        @Test("Saving sets her name at once, so the one name sheet stops asking before it goes")
        func nameIsSetAtOnce() async {
            await AssistantRestockTestSupport.asIdentity(nil, named: nil) {
                let kept = NSUbiquitousKeyValueStore.default.string(forKey: "Assistant.displayName")
                defer { NSUbiquitousKeyValueStore.default.set(kept, forKey: "Assistant.displayName") }

                let write = AssistantNameSheet.commit("Bea", in: nil)
                let hasName = ClassroomIdentity.displayName != nil
                #expect(ClassroomIdentity.displayName == "Bea")
                #expect(!AssistantFirstRun.asksForName(
                    setupShowing: false, setupDone: true, isSample: false, hasName: hasName))
                await write.value
            }
        }
    }
}
