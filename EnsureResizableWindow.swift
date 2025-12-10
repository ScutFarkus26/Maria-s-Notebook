#if os(macOS)
import SwiftUI
import AppKit

/// Inserts a lightweight NSView into the view hierarchy that, when attached to a window,
/// ensures the window is resizable and applies optional min/max content sizes.
struct EnsureResizableWindow: NSViewRepresentable {
    var minSize: NSSize? = NSSize(width: 900, height: 600)
    var maxSize: NSSize? = nil

    func makeNSView(context: Context) -> ResizableFlagView {
        let v = ResizableFlagView()
        v.minSize = minSize
        v.maxSize = maxSize
        return v
    }

    func updateNSView(_ nsView: ResizableFlagView, context: Context) {
        nsView.minSize = minSize
        nsView.maxSize = maxSize
        // If the view is already in a window, apply immediately
        if let win = nsView.window {
            apply(to: win, minSize: minSize, maxSize: maxSize)
        }
    }

    private func apply(to window: NSWindow, minSize: NSSize?, maxSize: NSSize?) {
        window.styleMask.insert(.resizable)
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        if let min = minSize { window.contentMinSize = min } else { window.contentMinSize = .zero }
        if let max = maxSize { window.contentMaxSize = max } else { window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude) }
    }
}

final class ResizableFlagView: NSView {
    var minSize: NSSize?
    var maxSize: NSSize?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let win = window else { return }
        win.styleMask.insert(.resizable)
        win.contentResizeIncrements = NSSize(width: 1, height: 1)
        if let minSize { win.contentMinSize = minSize } else { win.contentMinSize = .zero }
        if let maxSize { win.contentMaxSize = maxSize } else { win.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude) }
    }
}
#endif

