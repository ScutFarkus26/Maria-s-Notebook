/// The decision behind `onChangeWhenVisible` / `onReceiveWhenVisible`, kept
/// free of SwiftUI so it can be tested.
///
/// A screen is hidden two ways: it disappeared (a `TabView` keeps visited
/// tabs alive behind the others), or it is still there in a Mac window that
/// nobody can see (minimized, covered, on another Space). Either way a
/// trigger only marks it stale, and it catches up once when it can be seen.
struct WhenVisibleGate: Equatable {
    /// Between `onAppear` and `onDisappear`.
    private(set) var isAppeared = false
    /// Whether the window can be seen: the Mac's occlusion state, true until
    /// told otherwise and always true on iPhone and iPad.
    private(set) var isWindowVisible = true
    private(set) var isStale = false

    /// On screen: appeared, in a window someone can see.
    var isVisible: Bool { isAppeared && isWindowVisible }

    /// A trigger fired: true when the action should run now; otherwise the
    /// screen is hidden and is only marked stale.
    mutating func request() -> Bool {
        guard isVisible else {
            isStale = true
            return false
        }
        return true
    }

    /// The screen appeared: true when a request arrived while it was hidden
    /// and the caller wants it caught up here. A screen that reloads on its
    /// own appear (`catchUp == false`) has nothing left to catch up. One that
    /// appears in a window nobody can see keeps its catch-up until the window
    /// comes back.
    mutating func appear(catchUp: Bool) -> Bool {
        isAppeared = true
        guard catchUp else {
            isStale = false
            return false
        }
        guard isWindowVisible else { return false }
        defer { isStale = false }
        return isStale
    }

    mutating func disappear() {
        isAppeared = false
    }

    /// The window's visibility changed. True when it just came back into
    /// view with this screen on it and a request arrived while nobody could
    /// see it: run the action once now. This catch-up ignores `catchUp`,
    /// because a screen's own `.task` / `.onAppear` doesn't run again when
    /// its window is un-minimized or uncovered.
    mutating func windowVisibilityChanged(_ visible: Bool) -> Bool {
        let cameBack = visible && !isWindowVisible
        isWindowVisible = visible
        guard cameBack, isAppeared, isStale else { return false }
        isStale = false
        return true
    }
}
