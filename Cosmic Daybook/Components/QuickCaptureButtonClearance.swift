import SwiftUI

/// Leaves room below a phone list's last row for the floating quick-capture
/// button, which otherwise sits over that row's trailing controls (an
/// attendance row's note button, a report row's chevron) with no way to scroll
/// them out from under it. Safe-area padding rather than content margins, so
/// the horizontal scrollers inside the rows keep their height.
private struct QuickCaptureButtonClearance: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content.safeAreaPadding(.bottom, horizontalSizeClass == .compact ? 64 : 0)
        #else
        content
        #endif
    }
}

extension View {
    func quickCaptureButtonClearance() -> some View {
        modifier(QuickCaptureButtonClearance())
    }
}
