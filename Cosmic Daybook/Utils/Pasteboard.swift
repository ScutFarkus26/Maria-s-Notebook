//  Pasteboard.swift
//  Cosmic Daybook
//
//  One place for the macOS/iOS split when copying plain text, so the
//  "copy this name" menu items don't each carry their own `#if os(macOS)`.
//  Touches AppKit/UIKit pasteboards, so it stays on the main actor.

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Pasteboard {
    /// Replaces the system pasteboard contents with `string`.
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}
