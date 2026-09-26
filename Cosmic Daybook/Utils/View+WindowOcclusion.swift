import SwiftUI

extension View {
    /// Calls `action` with whether this view's window can be seen on the Mac:
    /// once when the view joins its window, then on every change. Minimized,
    /// fully covered, on another Space, hidden with the app, or behind the
    /// lock screen all read as `false`; a window whose state isn't known yet
    /// reads as `true`.
    ///
    /// Elsewhere it adds nothing and never calls `action`: on iPhone and iPad
    /// `onAppear` / `onDisappear` and `scenePhase` already follow what the
    /// user can see.
    func onWindowVisibilityChange(perform action: @escaping (Bool) -> Void) -> some View {
        #if os(macOS)
        background { WindowOcclusionProbe(onChange: action) }
        #else
        self
        #endif
    }
}
