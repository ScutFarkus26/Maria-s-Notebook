// SmartTextEditor.swift
// Platform-specific text editor with Apple Intelligence support

import SwiftUI

#if os(iOS)
import UIKit

struct SmartTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var triggerTool: Int // Change this to trigger actions

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.delegate = context.coordinator

        // Enable Apple Intelligence
        if #available(iOS 18.0, *) {
            textView.writingToolsBehavior = .complete
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }

        if context.coordinator.lastTrigger != triggerTool {
            // Trigger Action: Select All + Activate
            uiView.becomeFirstResponder()
            uiView.selectAll(nil)
            context.coordinator.lastTrigger = triggerTool
            // On iOS, selection automatically brings up the toolbar.
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SmartTextEditor
        var lastTrigger = 0
        init(_ parent: SmartTextEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
    }
}

#elseif os(macOS)
import AppKit

struct SmartTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var triggerTool: Int // Change this to trigger actions

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.drawsBackground = false

        // Enable Apple Intelligence
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .complete
        }
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        // Update text programmatically - prevent binding feedback loop
        if nsView.string != text {
            context.coordinator.isProgrammaticEdit = true
            nsView.string = text
            context.coordinator.isProgrammaticEdit = false
        }

        // Defer triggerTool actions to next run loop to avoid layout recursion
        if context.coordinator.lastTrigger != triggerTool {
            context.coordinator.lastTrigger = triggerTool

            // Store references for deferred execution
            let textView = nsView
            let window = nsView.window

            // Defer responder/selection/actions to avoid triggering layout during updateNSView
            DispatchQueue.main.async {
                // Guard that window and textView are still valid
                guard let win = window, textView.window == win else { return }

                // Focus editor and select all
                win.makeFirstResponder(textView)
                textView.selectAll(nil)

                // Show writing tools (macOS 15.2+)
                if #available(macOS 15.2, *) {
                    NSApp.sendAction(#selector(NSTextView.showWritingTools(_:)), to: nil, from: nil)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SmartTextEditor
        var lastTrigger = 0
        /// Flag to prevent binding updates during programmatic string changes
        var isProgrammaticEdit = false

        init(_ parent: SmartTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            // Ignore changes that originate from programmatic updates to prevent feedback loops
            guard !isProgrammaticEdit else { return }
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
#endif
