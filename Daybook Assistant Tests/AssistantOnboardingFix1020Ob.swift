import Foundation
import CloudKit
import Testing
import UserNotifications
@testable import Daybook_Assistant

// Bug hunt 2026-10-20, onboarding (#20, #24, #25): Not Now on setup's
// reminder page left the front-desk reminder on, so iOS still asked about
// notifications; a refusal in setup still read "Arrival reminder 8:15 AM";
// an iCloud status CloudKit couldn't tell read "Signed in to iCloud"; and
// the tabs' name sheet could open over the first-run prompt's.
@Suite("Assistant onboarding fixes 2026-10-20")
@MainActor
struct AssistantOnboardingFix1020Ob {

    private let defaults = AssistantTestSupport.makeDefaults()

    // MARK: - #20 Not Now

    @Test("Not Now turns off the front-desk reminder too, so nothing asks about notifications")
    func notNowTurnsBothOff() {
        AssistantSetupReminder.decline(defaults)
        #expect(!ArrivalReminder.isEnabled(defaults))
        #expect(!FrontDeskEmailReminder.isEnabled(defaults))
    }

    @Test("Turn On after Not Now turns both back on")
    func turnOnAfterNotNow() async {
        AssistantSetupReminder.decline(defaults)
        let center = AnsweringCenter(answer: .authorized)
        let allowed = await AssistantSetupReminder.turnOn(center: center, defaults: defaults)
        #expect(allowed)
        #expect(ArrivalReminder.isEnabled(defaults))
        #expect(FrontDeskEmailReminder.isEnabled(defaults))
    }

    // MARK: - #24 Refused in setup

    @Test("Turn On asks once and reads the answer: refused means notifications are off")
    func refusedIsRead() async {
        let center = AnsweringCenter(answer: .denied)
        let allowed = await AssistantSetupReminder.turnOn(center: center, defaults: defaults)
        #expect(center.asks == 1)
        #expect(!allowed)
    }

    @Test("Turn On doesn't ask again once she has answered, and reads that answer")
    func answeredBefore() async {
        let center = AnsweringCenter(answer: .denied, status: .denied)
        let allowed = await AssistantSetupReminder.turnOn(center: center, defaults: defaults)
        #expect(center.asks == 0)
        #expect(!allowed)

        let allowedCenter = AnsweringCenter(answer: .authorized, status: .provisional)
        #expect(await AssistantSetupReminder.turnOn(center: allowedCenter, defaults: defaults))
        #expect(allowedCenter.asks == 0)
    }

    @Test("All Set says Notifications off when they're refused, the time when allowed, Off when turned off")
    func summaryLine() {
        let minutes = 8 * 60 + 15
        let time = FrontDeskEmailReminder.timeString(minutes)
        #expect(AssistantSetupReminder.summary(reminderOn: true, minutes: minutes, notificationsOff: true)
            == "Notifications off")
        #expect(AssistantSetupReminder.summary(reminderOn: true, minutes: minutes, notificationsOff: false) == time)
        #expect(AssistantSetupReminder.summary(reminderOn: false, minutes: minutes, notificationsOff: true) == "Off")
        #expect(AssistantSetupReminder.summary(reminderOn: false, minutes: minutes, notificationsOff: false) == "Off")
    }

    @Test("Only a refusal counts as off: allowed, quiet or not asked yet don't")
    func whatCountsAsOff() {
        #expect(AssistantSetupReminder.notificationsOff(.denied))
        #expect(!AssistantSetupReminder.notificationsOff(.authorized))
        #expect(!AssistantSetupReminder.notificationsOff(.provisional))
        #expect(!AssistantSetupReminder.notificationsOff(.ephemeral))
        #expect(!AssistantSetupReminder.notificationsOff(.notDetermined))
    }

    // MARK: - #25 iCloud wording

    @Test("An iCloud status CloudKit couldn't tell still reads as checking, not signed in")
    func undeterminedIsChecking() {
        #expect(AssistantICloudPage.isChecking(nil))
        #expect(AssistantICloudPage.isChecking(.couldNotDetermine))
        #expect(!AssistantICloudPage.isChecking(.available))
    }

    // #25's one name sheet: `AssistantOnboardingFix1020RoundD` (one rule, on the tabs).
}

/// Answers the permission question the way it's told, and from then on
/// reports that answer, as iOS does.
private final class AnsweringCenter: ReminderCenter {
    private let answer: UNAuthorizationStatus
    private var status: UNAuthorizationStatus
    private(set) var asks = 0

    init(answer: UNAuthorizationStatus, status: UNAuthorizationStatus = .notDetermined) {
        self.answer = answer
        self.status = status
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async -> Bool {
        asks += 1
        status = answer
        return answer == .authorized
    }

    func pendingRequests() async -> [UNNotificationRequest] { [] }

    func removePendingRequests(withIdentifiers identifiers: [String]) {}

    func add(_ request: UNNotificationRequest) async throws {}
}
