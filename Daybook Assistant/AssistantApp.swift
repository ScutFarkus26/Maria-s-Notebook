import SwiftUI
import UserNotifications

/// Entry point for the assistant's companion app.
///
/// A deliberately small app: it accepts the lead guide's classroom share and
/// then does one job, attendance for today. Everything it touches is code
/// shared with Cosmic Daybook, so a change to the attendance rules there
/// reaches here without being reimplemented.
@main
struct AssistantApp: App {
    @UIApplicationDelegateAdaptor(ShareAcceptanceAppDelegate.self) private var appDelegate

    @State private var bootstrapper: AssistantBootstrapper
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = ArrivalReminderTaps.shared
        let bootstrapper = AssistantBootstrapper()
        _bootstrapper = State(initialValue: bootstrapper)
        // A sync push can relaunch the app in the background with no window,
        // and then the window's task below never runs: starting here opens
        // the store, so it imports the change and the pickup reminders follow
        // it (`EarlyPickupReminderUpkeep`). The window's call is then a no-op.
        if !AssistantBootstrapper.isRunningUnitTests {
            Task { await bootstrapper.start() }
        }
    }

    var body: some Scene {
        WindowGroup {
            AssistantRootView()
                .environment(bootstrapper)
                .task {
                    // A hosted test run must not open the simulator's real
                    // (Production) store: the tests build their own.
                    guard !AssistantBootstrapper.isRunningUnitTests else { return }
                    await bootstrapper.start()
                }
        }
        // Coming back, or leaving for the background: the pickup reminders
        // catch up with changes made while the attendance screen wasn't
        // running (`EarlyPickupReminderUpkeep`). Coming back also asks about
        // iCloud again: she may have signed in from Settings meanwhile, and
        // `CKAccountChanged` doesn't always arrive.
        .onChange(of: scenePhase) { _, phase in
            bootstrapper.pickupRemindersMayHaveChanged()
            if phase == .active, !AssistantBootstrapper.isRunningUnitTests {
                Task { await bootstrapper.refreshAccountStatus() }
            }
        }
    }
}
