/// What a window-occlusion probe tells the view it sits in, kept free of
/// AppKit so the rules can be tested on any platform.
///
/// A view starts out assuming its window can be seen: unknown counts as
/// visible, so a probe that never hears from AppKit leaves the view working
/// exactly as it did before there was a probe.
struct WindowVisibilityTracker: Equatable {
    /// The last value handed to the view; nil while unknown.
    private(set) var lastReported: Bool?

    /// The probe joined a window. A window that is ordered in (on screen on
    /// any Space, or in the Dock) has a current occlusion state; one still
    /// being built has none yet and counts as visible until AppKit posts a
    /// change. Always reported, so a view whose own state outlived an earlier
    /// probe is brought up to date.
    mutating func attached(isOrderedIn: Bool, isVisible: Bool) -> Bool {
        let visible = isOrderedIn ? isVisible : true
        lastReported = visible
        return visible
    }

    /// AppKit posted an occlusion change: the value to report, or nil when
    /// visibility didn't actually flip.
    mutating func occlusionChanged(isVisible: Bool) -> Bool? {
        guard isVisible != lastReported else { return nil }
        lastReported = isVisible
        return isVisible
    }

    /// The probe left its window: unknown again, which counts as visible.
    mutating func detached() -> Bool? {
        defer { lastReported = nil }
        return lastReported == false ? true : nil
    }
}
