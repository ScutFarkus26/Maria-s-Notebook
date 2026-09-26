#if os(macOS)
import AppKit
import OSLog
import SwiftUI

/// A zero-size view that tells SwiftUI whether its window can be seen.
///
/// AppKit calls a window occluded when no part of it is visible: minimized,
/// fully covered, on another Space, hidden with the app, or behind the screen
/// saver or lock screen. None of that reaches SwiftUI on the Mac: the views
/// don't disappear and `scenePhase` doesn't change, so work gated on those
/// keeps running for a window nobody can see. Apple's guidance is to watch
/// the occlusion state and halt the work instead.
///
/// Use it through `.onWindowVisibilityChange(perform:)`.
struct WindowOcclusionProbe: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> WindowOcclusionProbeView {
        let view = WindowOcclusionProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: WindowOcclusionProbeView, context: Context) {
        nsView.onChange = onChange
    }

    static func dismantleNSView(_ nsView: WindowOcclusionProbeView, coordinator: ()) {
        nsView.dismantle()
    }
}

final class WindowOcclusionProbeView: NSView {
    private static let logger = Logger.ui

    var onChange: ((Bool) -> Void)?
    private var tracker = WindowVisibilityTracker()
    private var observation: NotificationCenter.ObservationToken?
    /// The newest value not yet handed to `onChange`.
    private var pendingValue: Bool?

    deinit {
        if let observation {
            NotificationCenter.default.removeObserver(observation)
        }
    }

    /// Never the target of a click: it sits behind the content it reports on.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else {
            if let visible = tracker.detached() { deliver(visible) }
            return
        }
        observation = NotificationCenter.default.addObserver(
            of: window,
            for: .didChangeOcclusionState
        ) { [weak self] message in
            self?.occlusionDidChange(in: message.window)
        }
        let isOrderedIn = window.isVisible || window.isMiniaturized
        deliver(tracker.attached(
            isOrderedIn: isOrderedIn,
            isVisible: window.occlusionState.contains(.visible)
        ))
    }

    /// SwiftUI removed the view: nothing more is reported.
    func dismantle() {
        onChange = nil
        pendingValue = nil
        stopObserving()
    }

    private func occlusionDidChange(in window: NSWindow) {
        guard window === self.window,
              let visible = tracker.occlusionChanged(isVisible: window.occlusionState.contains(.visible))
        else { return }
        deliver(visible)
    }

    private func stopObserving() {
        guard let observation else { return }
        NotificationCenter.default.removeObserver(observation)
        self.observation = nil
    }

    /// Hands the newest value over on the next main-actor turn: a move into or
    /// out of a window happens inside a SwiftUI update, and the handler
    /// changes view state. Values that arrive together collapse to the last.
    private func deliver(_ visible: Bool) {
        let isScheduled = pendingValue != nil
        pendingValue = visible
        guard !isScheduled else { return }
        Task { [weak self] in
            self?.flushPendingValue()
        }
    }

    private func flushPendingValue() {
        guard let visible = pendingValue else { return }
        pendingValue = nil
        guard let onChange else { return }
        let windowNumber = window?.windowNumber ?? 0
        Self.logger.info("Window \(windowNumber, privacy: .public) visible: \(visible, privacy: .public)")
        onChange(visible)
    }
}
#endif
