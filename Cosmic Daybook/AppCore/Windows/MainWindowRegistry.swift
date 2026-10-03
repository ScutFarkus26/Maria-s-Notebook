#if os(macOS)
import AppKit

/// The open main windows (the `mainWindow` scene), so a request every main
/// window hears is answered by just one of them.
///
/// `EnsureResizableWindow` registers each one, and so does
/// `OpenWindowOnNotificationModifier` (which also counts a window still
/// loading or onboarding). Only `RootView` attaches the first, and `RootView`
/// and the modifier are built only by the main `WindowGroup` — detail windows
/// never host them — so every window here is a main window.
/// SwiftUI doesn't document the identifiers it gives windows, so they aren't used.
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

    /// Whether `window` is the main window that answers a request every main
    /// window hears (`MainWindowCandidate.indexToAnswer`). True for exactly one
    /// registered window while any is open; false for the others, and for a
    /// window that isn't registered.
    func answersRequests(in window: NSWindow?) -> Bool {
        pruneClosedWindows()
        guard let window, let index = entries.firstIndex(where: { $0.window === window }) else { return false }
        return MainWindowCandidate.indexToAnswer(candidates) == index
    }

    /// One candidate per entry, in entry order.
    private var candidates: [MainWindowCandidate] {
        entries.map { entry in
            MainWindowCandidate(
                isOnScreen: entry.window?.isVisible ?? false,
                isMiniaturized: entry.window?.isMiniaturized ?? false,
                lastUsed: entry.lastUsed
            )
        }
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
