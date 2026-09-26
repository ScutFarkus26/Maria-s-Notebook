#if os(macOS)
import AppKit

/// The open main windows (the `mainWindow` scene), so the desktop companion can
/// bring one forward instead of opening another full main window per action.
///
/// `EnsureResizableWindow` registers each one. Only `RootView` attaches it, and
/// `RootView` is built only by the main `WindowGroup` — detail windows and the
/// companion never host it — so every window here is a main window. SwiftUI
/// doesn't document the identifiers it gives windows, so they aren't used.
final class MainWindowRegistry {
    static let shared = MainWindowRegistry()

    private struct Entry {
        weak var window: NSWindow?
        var lastUsed: Int
        let observations: [NotificationCenter.ObservationToken]
    }

    private var entries: [Entry] = []
    private var useCount = 0

    /// Starts tracking a main window; a window already tracked is left as is.
    func register(_ window: NSWindow) {
        pruneClosedWindows()
        guard !entries.contains(where: { $0.window === window }) else { return }
        let center = NotificationCenter.default
        let observations = [
            center.addObserver(of: window, for: .didBecomeMain) { [weak self] message in
                self?.noteUse(of: message.window)
            },
            center.addObserver(of: window, for: .willClose) { [weak self] message in
                self?.forget(message.window)
            }
        ]
        entries.append(Entry(window: window, lastUsed: nextUse(), observations: observations))
    }

    /// Brings the most recently used open main window forward — out of the
    /// Dock first if it is minimized — and makes it key. False when no main
    /// window is open, so the caller opens one.
    func bringMostRecentForward() -> Bool {
        pruneClosedWindows()
        let candidates = entries.map { entry in
            MainWindowCandidate(
                isOnScreen: entry.window?.isVisible ?? false,
                isMiniaturized: entry.window?.isMiniaturized ?? false,
                lastUsed: entry.lastUsed
            )
        }
        guard let index = MainWindowCandidate.indexToBringForward(candidates),
              let window = entries[index].window else { return false }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    private func nextUse() -> Int {
        useCount += 1
        return useCount
    }

    private func noteUse(of window: NSWindow) {
        guard let index = entries.firstIndex(where: { $0.window === window }) else { return }
        entries[index].lastUsed = nextUse()
    }

    private func forget(_ window: NSWindow) {
        removeEntries { $0.window === window }
    }

    /// Drops windows that went away without a close notification.
    private func pruneClosedWindows() {
        removeEntries { $0.window == nil }
    }

    private func removeEntries(where isRemoved: (Entry) -> Bool) {
        for entry in entries where isRemoved(entry) {
            for observation in entry.observations {
                NotificationCenter.default.removeObserver(observation)
            }
        }
        entries.removeAll(where: isRemoved)
    }
}
#endif
