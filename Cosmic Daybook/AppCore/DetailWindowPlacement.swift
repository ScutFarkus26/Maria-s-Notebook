#if os(macOS)
import AppKit
import SwiftUI

extension Scene {
    /// Opens each new window centred on the display instead of leaving it to
    /// AppKit's cascade.
    ///
    /// The cascade starts from the top-left of the current space. On the
    /// desktop that reads fine — the window tucks under the menu bar with the
    /// rest of the app visible around it. Inside a full-screen space there is
    /// no menu bar to cascade below, so a detail window opens flush in the
    /// corner and reads as a stray panel rather than the thing you just asked
    /// for.
    ///
    /// The size comes from the content's ideal size, clamped to the display so
    /// a tall window still fits on a short screen.
    func centeredOnOpen() -> some Scene {
        defaultWindowPlacement { content, context in
            let display = context.defaultDisplay.visibleRect
            let ideal = content.sizeThatFits(.unspecified)
            let size = CGSize(
                width: min(ideal.width, display.width),
                height: min(ideal.height, display.height)
            )
            return WindowPlacement(.center, size: size)
        }
    }
}

/// Lets a window share the space of a full-screen window instead of being sent
/// off to one of its own.
///
/// Without `.fullScreenAuxiliary`, opening a detail window while the main
/// window is in native full screen hands the new window a fresh space. That
/// space has no wallpaper behind it, so the screen reads as black with the
/// detail window stranded in it — the main window is still there, just in the
/// space you were pulled out of. With the behaviour set, the window floats
/// over the main window where you asked for it.
///
/// The companion window needs the same treatment; see
/// `DesktopNotebookCompanionView`.
struct FullScreenAuxiliaryWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> FullScreenAuxiliaryView {
        FullScreenAuxiliaryView()
    }

    func updateNSView(_ nsView: FullScreenAuxiliaryView, context: Context) {}
}

final class FullScreenAuxiliaryView: NSView {
    private var isConfigured = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !isConfigured, window != nil else { return }
        // Deferred: window mutations during the attach layout pass are the
        // pattern that trips AppKit elsewhere in this app.
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.collectionBehavior.formUnion([.fullScreenAuxiliary])
            self.isConfigured = true
        }
    }
}
#endif
