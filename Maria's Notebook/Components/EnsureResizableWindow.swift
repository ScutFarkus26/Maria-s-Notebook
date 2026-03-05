#if os(macOS)
import SwiftUI
import AppKit

/// Inserts a lightweight NSView into the view hierarchy that, when attached to a window,
/// ensures the window is resizable and applies optional min/max content sizes.
struct EnsureResizableWindow: NSViewRepresentable {
    var minSize: NSSize? = NSSize(width: 900, height: 600)
    var maxSize: NSSize?

    func makeNSView(context: Context) -> ResizableFlagView {
        let v = ResizableFlagView()
        v.minSize = minSize
        v.maxSize = maxSize
        return v
    }

    func updateNSView(_ nsView: ResizableFlagView, context: Context) {
        // Update stored values
        nsView.minSize = minSize
        nsView.maxSize = maxSize
        
        // Schedule window updates to next run loop to avoid layout recursion
        // Only apply if values actually changed (cached in ResizableFlagView)
        if nsView.window != nil {
            nsView.scheduleWindowUpdate()
        }
    }
}

final class ResizableFlagView: NSView {
    var minSize: NSSize?
    var maxSize: NSSize?
    
    // Cache last applied values to avoid redundant updates
    private var lastAppliedMinSize: NSSize?
    private var lastAppliedMaxSize: NSSize?
    private var hasScheduledUpdate = false
    
    /// Schedule window property updates to the next run loop to prevent layout recursion
    func scheduleWindowUpdate() {
        // Prevent duplicate scheduling
        guard !hasScheduledUpdate else { return }
        hasScheduledUpdate = true
        
        // Check if values actually changed
        guard minSize != lastAppliedMinSize || maxSize != lastAppliedMaxSize else {
            hasScheduledUpdate = false
            return
        }
        
        // Defer to next run loop to avoid triggering layout during active layout pass
        Task { @MainActor [weak self] in
            guard let self = self, let win = self.window else {
                self?.hasScheduledUpdate = false
                return
            }

            // Apply window mutations outside of layout pass
            self.apply(to: win)
            self.hasScheduledUpdate = false
        }
    }
    
    private func apply(to window: NSWindow) {
        // Only update if values changed (idempotent)
        let effectiveMin = minSize ?? .zero
        let effectiveMax = maxSize ?? NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        
        guard effectiveMin != lastAppliedMinSize || effectiveMax != lastAppliedMaxSize else {
            return
        }
        
        window.styleMask.insert(.resizable)
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        window.contentMinSize = effectiveMin
        window.contentMaxSize = effectiveMax
        
        // Update cache
        lastAppliedMinSize = minSize
        lastAppliedMaxSize = maxSize
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Defer window mutations to avoid layout recursion during window attachment
        guard window != nil else { return }
        scheduleWindowUpdate()
    }
}

/// Inserts a zero-size NSView that programmatically resizes its hosting window
/// when `targetSize` changes. Useful for sheet windows that don't respond to
/// SwiftUI `.frame()` changes after initial presentation.
struct SheetWindowResizer: NSViewRepresentable {
    var targetSize: NSSize

    func makeNSView(context: Context) -> SheetResizeView {
        let v = SheetResizeView()
        v.targetSize = targetSize
        return v
    }

    func updateNSView(_ nsView: SheetResizeView, context: Context) {
        guard nsView.targetSize != targetSize else { return }
        nsView.targetSize = targetSize
        if nsView.window != nil {
            nsView.scheduleResize()
        }
    }
}

final class SheetResizeView: NSView {
    var targetSize: NSSize = .zero
    private var lastAppliedSize: NSSize = .zero
    private var hasScheduledResize = false

    func scheduleResize() {
        guard !hasScheduledResize else { return }
        guard targetSize != lastAppliedSize else { return }
        hasScheduledResize = true

        Task { @MainActor [weak self] in
            guard let self, let win = self.window else {
                self?.hasScheduledResize = false
                return
            }
            self.resizeWindow(win)
            self.hasScheduledResize = false
        }
    }

    private func resizeWindow(_ window: NSWindow) {
        let newSize = targetSize
        guard newSize != lastAppliedSize else { return }
        lastAppliedSize = newSize

        // Anchor the top-left corner: grow downward and to the right
        var frame = window.frame
        let dw = newSize.width - frame.size.width
        let dh = newSize.height - frame.size.height
        frame.size = NSSize(width: newSize.width, height: newSize.height)
        frame.origin.y -= dh  // keep top edge pinned
        _ = dw // width grows to the right naturally

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        scheduleResize()
    }
}
#endif
