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

    @State private var bootstrapper = AssistantBootstrapper()

    init() {
        UNUserNotificationCenter.current().delegate = ArrivalReminderTaps.shared
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
    }
}
