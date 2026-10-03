/// One open main window as `MainWindowRegistry` sees it when choosing which
/// one answers a request; kept free of AppKit so the choice can be tested anywhere.
struct MainWindowCandidate: Equatable {
    /// Ordered in: on screen on some Space, possibly covered.
    var isOnScreen: Bool
    /// In the Dock.
    var isMiniaturized: Bool
    /// Larger is more recent: when it was registered, then each time it
    /// became the app's main window.
    var lastUsed: Int

    /// The preferred open window: the most recently used one on screen,
    /// else the most recently used one in the Dock. Nil when none is open
    /// (closed windows are neither).
    static func indexToBringForward(_ candidates: [MainWindowCandidate]) -> Int? {
        let open = candidates.indices.filter { candidates[$0].isOnScreen || candidates[$0].isMiniaturized }
        let onScreen = open.filter { !candidates[$0].isMiniaturized }
        let pool = onScreen.isEmpty ? open : onScreen
        return pool.max { candidates[$0].lastUsed < candidates[$1].lastUsed }
    }

    /// The one window that answers a request every main window hears (the
    /// window-opening notifications), so the request is handled once however
    /// many are open: the window `indexToBringForward` picks, else — none on
    /// screen or in the Dock, as while the app is hidden — the most recently
    /// used. Nil only when there is no candidate at all.
    static func indexToAnswer(_ candidates: [MainWindowCandidate]) -> Int? {
        indexToBringForward(candidates)
            ?? candidates.indices.max { candidates[$0].lastUsed < candidates[$1].lastUsed }
    }
}
