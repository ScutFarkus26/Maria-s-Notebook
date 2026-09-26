//
//  MCPIdleQuitController.swift
//  Cosmic Daybook
//
//  Drives MCPIdleQuitPolicy for an MCP-only launch on the Mac: counts the
//  connected Claude clients (from MCPServerService) and the app's open
//  windows (from AppKit), keeps one countdown task in step with the
//  policy's deadline, and quits with NSApp.terminate — an ordinary quit, so
//  the quit backup in AutoBackupAppDelegate runs as it does on ⌘Q. A normal
//  launch never creates one.
//

#if os(macOS)
import AppKit
import OSLog

@MainActor
final class MCPIdleQuitController {
    private static let logger = Logger.mcpServer

    /// Slack the countdown may take so the system can coalesce the wake-up;
    /// "about ten minutes" does not need to be exact.
    private static let countdownTolerance: Duration = .seconds(30)

    /// The window changes that can open or close a window, or show or hide one.
    private static let windowNotifications: [Notification.Name] = [
        NSWindow.didChangeOcclusionStateNotification,
        NSWindow.willCloseNotification,
        NSWindow.didBecomeKeyNotification,
        NSWindow.didMiniaturizeNotification,
        NSWindow.didDeminiaturizeNotification,
        NSApplication.didUnhideNotification
    ]

    private var policy: MCPIdleQuitPolicy
    private var countdown: Task<Void, Never>?
    private var scheduledDeadline: MCPIdleQuitPolicy.Instant?
    private var observers: [any NSObjectProtocol] = []

    init(idleInterval: Duration = MCPIdleQuitPolicy.defaultIdleInterval) {
        policy = MCPIdleQuitPolicy(idleInterval: idleInterval, launchedAt: .now)
    }

    func start() {
        let service = MCPServerService.shared
        service.onConnectedClientCountChange = { [weak self] count in
            self?.connectionCountChanged(to: count)
        }
        observeWindows()
        policy.connectionCountChanged(to: service.connectedClientCount, at: .now)
        recountWindows()
        let minutes = policy.idleInterval.components.seconds / 60
        Self.logger.notice(
            "MCP-only launch: no main window; quits \(minutes, privacy: .public) min after the last client leaves"
        )
    }

    // MARK: - Inputs

    private func connectionCountChanged(to count: Int) {
        policy.connectionCountChanged(to: count, at: .now)
        reschedule()
    }

    /// The window notifications arrive on the main queue; each one schedules
    /// a recount on the main actor, which also lets a closing window finish
    /// closing before it is counted.
    private func observeWindows() {
        let center = NotificationCenter.default
        observers = Self.windowNotifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.recountWindows() }
            }
        }
    }

    private func recountWindows() {
        // A hidden app's windows read as not visible, but they are still open:
        // keep the count from before the hide until the app is shown again.
        // (A windowless MCP-only launch hidden by "Hide Others" stays at zero.)
        guard !NSApplication.shared.isHidden else { return }
        policy.windowCountChanged(to: Self.openWindowCount(), at: .now)
        reschedule()
    }

    /// The app's open windows, by the rule AppKit documents for a Dock click
    /// (`applicationShouldHandleReopen(_:hasVisibleWindows:)`): visible
    /// `NSWindow`s, not panels, with minimized ones counted as open. The app
    /// delegate's reopen uses it too, rather than the flag AppKit passes.
    static func openWindowCount() -> Int {
        NSApplication.shared.windows.count { window in
            !(window is NSPanel) && (window.isVisible || window.isMiniaturized)
        }
    }

    // MARK: - Countdown

    /// Keeps one countdown task aimed at the policy's deadline.
    private func reschedule() {
        let deadline = policy.quitDeadline
        guard deadline != scheduledDeadline else { return }
        scheduledDeadline = deadline
        countdown?.cancel()
        countdown = nil
        guard let deadline else { return }
        countdown = Task { [weak self] in
            do {
                try await Task.sleep(until: deadline, tolerance: Self.countdownTolerance, clock: .continuous)
            } catch {
                return // cancelled: a client connected, a window opened, or the deadline moved
            }
            self?.countdownElapsed()
        }
    }

    private func countdownElapsed() {
        // Count the windows afresh rather than trusting the notifications alone.
        recountWindows()
        guard policy.shouldQuit(at: .now) else {
            // Something is open again, or the wake came early: aim a fresh
            // countdown at whatever the deadline is now (none while busy).
            scheduledDeadline = nil
            reschedule()
            return
        }
        Self.logger.notice("MCP-only launch idle — no Claude client and no window — quitting")
        // Close the port first: a Claude session that starts while the quit
        // backup runs then finds it closed and its bridge starts a fresh copy
        // once this one has gone, instead of connecting to a process that is
        // about to exit.
        MCPServerService.shared.stopBeforeQuit()
        NSApplication.shared.terminate(nil)
    }
}
#endif
