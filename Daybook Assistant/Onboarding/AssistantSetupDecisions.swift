import Foundation
import SwiftUI
import UserNotifications

// What setup decides, apart from its pages (`AssistantSetupFlow`), for the
// tests (bug hunt 2026-10-20 #20, #24, #25, and review (d)).

/// What setup's reminder page does with her answer.
@MainActor
enum AssistantSetupReminder {
    static let refusedLine = "Notifications are off for this app. Turn them on in Settings."
    static let declinedInSetupKey = "Assistant.reminders.declinedInSetup"

    /// The reminder switches: the arrival and front-desk ones setup sets,
    /// and the early-pickup one, which is on unless she turns it off.
    enum Kind {
        case arrival, frontDesk, pickup
    }

    /// Not Now: no notifications for now. The arrival and front-desk
    /// reminders go off, and nothing asks iOS about notifications, the
    /// early-pickup reminder's question included
    /// (`ArrivalReminderFollower.askPermission`), until she turns a reminder
    /// on herself (`turnedOn`).
    static func decline(_ defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: ArrivalReminder.enabledKey)
        defaults.set(false, forKey: FrontDeskEmailReminder.enabledKey)
        defaults.set(true, forKey: declinedInSetupKey)
    }

    static func declinedInSetup(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: declinedInSetupKey)
    }

    /// She turned a reminder on, in setup or Classroom: the questions may be
    /// asked again, and the arrival reminder brings back the front-desk one
    /// that Not Now turned off with it. Without a Not Now, nothing changes.
    static func turnedOn(_ kind: Kind, defaults: UserDefaults = .standard) {
        guard declinedInSetup(defaults) else { return }
        defaults.removeObject(forKey: declinedInSetupKey)
        if kind == .arrival { defaults.set(true, forKey: FrontDeskEmailReminder.enabledKey) }
    }

    /// Turn On: the reminders on, iOS asked if it hasn't been, and the
    /// answer read back. Returns whether notifications may show.
    static func turnOn(
        center: any ReminderCenter = SystemReminderCenter(),
        defaults: UserDefaults = .standard
    ) async -> Bool {
        defaults.set(true, forKey: ArrivalReminder.enabledKey)
        // A Not Now before going back a page had turned this one off too.
        defaults.set(true, forKey: FrontDeskEmailReminder.enabledKey)
        defaults.removeObject(forKey: declinedInSetupKey)
        if await center.authorizationStatus() == .notDetermined {
            _ = await center.requestAuthorization()
        }
        return !notificationsOff(await center.authorizationStatus())
    }

    /// Only a refusal: allowed, quiet delivery, or not asked yet aren't off.
    static func notificationsOff(_ status: UNAuthorizationStatus) -> Bool {
        status == .denied
    }

    /// All Set's "Arrival reminder" line.
    static func summary(reminderOn: Bool, minutes: Int, notificationsOff: Bool) -> String {
        guard reminderOn else { return "Off" }
        return notificationsOff ? "Notifications off" : FrontDeskEmailReminder.timeString(minutes)
    }

    /// All Set's front-desk (or ParentLocker) reminder line, as Classroom's
    /// picker says it: "10 min before 9:00 AM".
    static func frontDeskSummary(on: Bool, leadMinutes: Int, dueAt: String, notificationsOff: Bool) -> String {
        guard on else { return "Off" }
        return notificationsOff ? "Notifications off" : "\(leadMinutes) min before \(dueAt)"
    }
}

/// Watches the three reminder switches wherever they change (setup,
/// Classroom, the pickup rows) and tells `AssistantSetupReminder.turnedOn`
/// when one goes on. On the tabs, which stay up under both screens.
struct ReminderSwitchesFollower: ViewModifier {
    @AppStorage(ArrivalReminder.enabledKey) private var arrivalOn = true
    @AppStorage(FrontDeskEmailReminder.enabledKey) private var frontDeskOn = FrontDeskEmailReminder.isOnByDefault
    @AppStorage(EarlyPickupReminder.enabledKey) private var pickupOn = true

    func body(content: Content) -> some View {
        content
            .onChange(of: arrivalOn) { _, on in if on { AssistantSetupReminder.turnedOn(.arrival) } }
            .onChange(of: frontDeskOn) { _, on in if on { AssistantSetupReminder.turnedOn(.frontDesk) } }
            .onChange(of: pickupOn) { _, on in if on { AssistantSetupReminder.turnedOn(.pickup) } }
    }
}

/// The first run's one rule for her name, which the tabs follow
/// (`AssistantTabs`): one place shows setup, and one sheet asks for a
/// missing name, so two can never be asked for at once (review (d), #2).
enum AssistantFirstRun {
    /// Whether the name sheet shows: a name is missing in the real class
    /// once setup is over. Setup asks for it itself, and while setup is up
    /// nothing else asks; an Apple Account change during setup is asked
    /// after it, unless she gave her name there. The sample class marks
    /// under no one's name.
    static func asksForName(setupShowing: Bool, setupDone: Bool, isSample: Bool, hasName: Bool) -> Bool {
        !setupShowing && setupDone && !isSample && !hasName
    }
}
