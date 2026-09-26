/// One open main window as the desktop companion sees it when choosing which
/// to bring forward; kept free of AppKit so the choice can be tested anywhere.
struct MainWindowCandidate: Equatable {
    /// Ordered in: on screen on some Space, possibly covered.
    var isOnScreen: Bool
    /// In the Dock.
    var isMiniaturized: Bool
    /// Larger is more recent: when it was registered, then each time it
    /// became the app's main window.
    var lastUsed: Int

    /// The window to bring forward: the most recently used one on screen,
    /// else the most recently used one in the Dock. Nil when none is open
    /// (closed windows are neither), so the caller opens a new main window
    /// as before.
    static func indexToBringForward(_ candidates: [MainWindowCandidate]) -> Int? {
        let open = candidates.indices.filter { candidates[$0].isOnScreen || candidates[$0].isMiniaturized }
        let onScreen = open.filter { !candidates[$0].isMiniaturized }
        let pool = onScreen.isEmpty ? open : onScreen
        return pool.max { candidates[$0].lastUsed < candidates[$1].lastUsed }
    }
}
