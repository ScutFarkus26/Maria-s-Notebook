//
//  IdleMemoryTrimController.swift
//  Cosmic Daybook
//
//  Drives IdleMemoryTrimPolicy on the Mac: a countdown armed when the app
//  resigns active and cancelled when it becomes active again, which trims
//  once it runs out; and a trim as the last main window closes. It keeps one
//  countdown task in step with the policy's deadline, as MCPIdleQuitController
//  does. Started once per process with the memory-pressure monitor
//  (AppDependencies).
//

#if os(macOS)
import AppKit

final class IdleMemoryTrimController {
    /// Slack the countdown may take so the system can coalesce the wake-up;
    /// "about ten minutes" does not need to be exact.
    private static let countdownTolerance: Duration = .seconds(60)

    private var policy: IdleMemoryTrimPolicy
    private let trim: (IdleMemoryTrimReason) -> Void
    private var countdown: Task<Void, Never>?
    private var scheduledDeadline: IdleMemoryTrimPolicy.Instant?
    private var observations: [NotificationCenter.ObservationToken] = []

    init(
        inactiveInterval: Duration = IdleMemoryTrimPolicy.defaultInactiveInterval,
        trim: @escaping (IdleMemoryTrimReason) -> Void
    ) {
        policy = IdleMemoryTrimPolicy(inactiveInterval: inactiveInterval)
        self.trim = trim
    }

    func start() {
        let center = NotificationCenter.default
        observations = [
            center.addObserver(of: NSApplication.self, for: .didResignActive) { [weak self] _ in
                self?.appResignedActive()
            },
            center.addObserver(of: NSApplication.self, for: .didBecomeActive) { [weak self] _ in
                self?.appBecameActive()
            },
            center.addObserver(of: NSWindow.self, for: .willClose) { [weak self] message in
                self?.windowWillClose(message.window)
            }
        ]
        // A launch that never became active (an MCP-only launch, or one
        // opened in the background) is already idle; nothing would arm it.
        if !NSApplication.shared.isActive {
            appResignedActive()
        }
    }

    // MARK: - Inputs

    private func appResignedActive() {
        policy.appResignedActive(at: .now)
        reschedule()
    }

    private func appBecameActive() {
        policy.appBecameActive()
        reschedule()
    }

    /// Runs as the window starts to close, while its content is still there
    /// to be recognised, so the other windows are counted without it.
    private func windowWillClose(_ window: NSWindow) {
        // A hidden app's windows read as not visible though they are still
        // open, so nothing can be counted; the inactive countdown (hiding
        // deactivates the app) covers that case.
        guard !NSApplication.shared.isHidden, Self.isMainWindow(window) else { return }
        let otherOpenMainWindows = NSApplication.shared.windows.count { other in
            other !== window && Self.isOpen(other) && Self.isMainWindow(other)
        }
        guard IdleMemoryTrimPolicy.shouldTrimOnWindowClose(
            closingMainWindow: true,
            otherOpenMainWindows: otherOpenMainWindows
        ) else { return }
        trim(.lastMainWindowClosed)
    }

    /// Open by the rule `MCPIdleQuitController` counts with — visible, or
    /// minimized — plus a background tab, which is ordered out while another
    /// tab of its window is showing.
    private static func isOpen(_ window: NSWindow) -> Bool {
        window.isVisible || window.isMiniaturized || window.tabbedWindows != nil
    }

    /// Whether `window` is one of the main window scene's. `RootView` puts
    /// `EnsureResizableWindow` in every main window and nowhere else — the
    /// rule `MainWindowRegistry` is built on — so its `ResizableFlagView`
    /// marks one. SwiftUI doesn't document the identifiers it gives windows,
    /// so they aren't used. Walked only when a window closes.
    private static func isMainWindow(_ window: NSWindow) -> Bool {
        guard let content = window.contentView else { return false }
        return containsMainWindowMarker(content)
    }

    private static func containsMainWindowMarker(_ view: NSView) -> Bool {
        view is ResizableFlagView || view.subviews.contains(where: containsMainWindowMarker)
    }

    // MARK: - Countdown

    /// Keeps one countdown task aimed at the policy's deadline.
    private func reschedule() {
        let deadline = policy.trimDeadline
        guard deadline != scheduledDeadline else { return }
        scheduledDeadline = deadline
        countdown?.cancel()
        countdown = nil
        guard let deadline else { return }
        countdown = Task { [weak self] in
            do {
                try await Task.sleep(until: deadline, tolerance: Self.countdownTolerance, clock: .continuous)
            } catch {
                return // cancelled: the app became active again
            }
            self?.countdownElapsed()
        }
    }

    private func countdownElapsed() {
        let shouldTrim = policy.countdownElapsed(at: .now)
        // This countdown has finished. After a trim there is no deadline until
        // the app has been active again; after an early wake, aim a fresh
        // countdown at the same one.
        countdown = nil
        scheduledDeadline = nil
        reschedule()
        if shouldTrim {
            trim(.appInactive)
        }
    }
}
#endif
