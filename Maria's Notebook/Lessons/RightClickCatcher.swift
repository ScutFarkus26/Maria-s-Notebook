#if os(macOS)
import AppKit
import SwiftUI

struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

class RightClickView: NSView {
    var onRightClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let e = NSApp.currentEvent {
            if e.type == .rightMouseDown { return self }
            if e.type == .otherMouseDown && e.buttonNumber == 2 { return self }
            if e.type == .leftMouseDown && e.modifierFlags.contains(.control) { return self }
        }
        return nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onRightClick?() }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?()
        } else {
            super.mouseDown(with: event)
        }
    }
}
#endif
