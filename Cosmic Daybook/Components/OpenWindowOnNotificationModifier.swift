#if os(macOS)
import AppKit
import SwiftUI

/// View modifier that listens for window-opening notifications and opens appropriate windows.
///
/// Every main window carries it, and every one hears each post, so only the
/// main window `MainWindowRegistry` picks — the most recently used one that is
/// open — opens the window; the others let the post go. One post, one
/// `openWindow`, however many main windows File ▸ New Window has opened (the
/// Keyboard Shortcuts window takes no value, so each extra call used to open
/// another copy). It registers its own window, so a main window that is still
/// loading or onboarding counts too.
struct OpenWindowOnNotificationModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @State private var host = HostWindow()

    func body(content: Content) -> some View {
        content
            .background { MainWindowProbe(host: host) }
            .onReceive(NotificationCenter.default.publisher(for: .openStudentDetailWindow)) { notification in
                if answersRequests, let studentID = notification.userInfo?["studentID"] as? UUID {
                    openWindow(id: "StudentDetailWindow", value: studentID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLessonDetailWindow)) { notification in
                if answersRequests, let lessonID = notification.userInfo?["lessonID"] as? UUID {
                    openWindow(id: "LessonDetailWindow", value: lessonID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openWorkDetailWindow)) { notification in
                if answersRequests, let workID = notification.userInfo?["workID"] as? UUID {
                    openWindow(id: "WorkDetailWindow", value: workID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openKeyboardShortcutsWindow)) { _ in
                if answersRequests {
                    openWindow(id: "KeyboardShortcutsWindow")
                }
            }
    }

    /// Whether this main window is the one that opens the requested window.
    private var answersRequests: Bool {
        MainWindowRegistry.shared.answersRequests(in: host.window)
    }
}

/// The window a view sits in, filled in by `MainWindowProbe`.
private final class HostWindow {
    weak var window: NSWindow?
}

/// A view behind the window's content that records its window in `host` and
/// registers that window with `MainWindowRegistry`; it takes no clicks. Only a
/// main window's root may host it.
private struct MainWindowProbe: NSViewRepresentable {
    let host: HostWindow

    func makeNSView(context: Context) -> MainWindowProbeView {
        let view = MainWindowProbeView()
        view.host = host
        return view
    }

    func updateNSView(_ nsView: MainWindowProbeView, context: Context) {
        nsView.host = host
        host.window = nsView.window
    }
}

private final class MainWindowProbeView: NSView {
    var host: HostWindow?

    /// Never the target of a click: it sits behind the window's content.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        host?.window = window
        if let window {
            MainWindowRegistry.shared.register(window)
        }
    }
}

// MARK: - Helper functions for posting window notifications

/// Opens a student detail in a new window
func openStudentInNewWindow(_ studentID: UUID) {
    NotificationCenter.default.post(
        name: .openStudentDetailWindow,
        object: nil,
        userInfo: ["studentID": studentID]
    )
}

/// Opens a lesson detail in a new window
func openLessonInNewWindow(_ lessonID: UUID) {
    NotificationCenter.default.post(
        name: .openLessonDetailWindow,
        object: nil,
        userInfo: ["lessonID": lessonID]
    )
}

/// Opens a work detail in a new window
func openWorkInNewWindow(_ workID: UUID) {
    NotificationCenter.default.post(
        name: .openWorkDetailWindow,
        object: nil,
        userInfo: ["workID": workID]
    )
}
#endif
