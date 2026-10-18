// OpenEditorsCheck.swift
// Whether switching classroom would throw away something being typed.
//
// A switch rebuilds every main window and closes every detail window, so a
// sheet open anywhere, or an observation open in its own window, would lose
// its text without a word (bug hunt 2026-10-17 #31). Sheets are presented by
// screens all over the app, so they aren't asked to register: the check looks
// at the windows themselves. Detail windows that hold typing count themselves
// in `OpenDetailWindows` (`DetailWindowClassroom`).

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum OpenEditorsCheck {
    /// Whether a sheet is up in any window or a detail window that holds
    /// typing is open.
    static func anyOpen(detailWindows: OpenDetailWindows = .shared) -> Bool {
        anyOpen(detailWindows: detailWindows, sheetUp: anySheetUp())
    }

    /// The same answer with whether a sheet is up already known.
    static func anyOpen(detailWindows: OpenDetailWindows, sheetUp: Bool) -> Bool {
        sheetUp || !detailWindows.isEmpty
    }

    #if os(macOS)
    /// A SwiftUI sheet, alert or confirmation on the Mac is a sheet attached
    /// to its window.
    private static func anySheetUp() -> Bool {
        NSApplication.shared.windows.contains { $0.attachedSheet != nil }
    }
    #else
    /// Whether any of `windows` has a sheet, popover or alert up. A sheet
    /// presented from a screen deep in the window is presented by its root
    /// view controller, which is what's asked. One already closing (the menu
    /// the switch was just chosen from, a popover tapped away) doesn't count
    /// (review c #10).
    static func anySheetPresented(in windows: [UIWindow]) -> Bool {
        windows.contains { window in
            window.rootViewController?.presentedViewController.map { !$0.isBeingDismissed } ?? false
        }
    }

    /// Every window of every scene: on iPad another window may hold the sheet.
    private static func anySheetUp() -> Bool {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return anySheetPresented(in: windows)
    }
    #endif
}

/// The detail windows open right now that hold typing (the Mac's "open in
/// its own window" scenes declared `countsAsEditor`), each counted while its
/// content is on screen and its classroom is showing.
final class OpenDetailWindows {
    static let shared = OpenDetailWindows()

    private var open: Set<UUID> = []

    var isEmpty: Bool { open.isEmpty }

    func opened(_ window: UUID) {
        open.insert(window)
    }

    func closed(_ window: UUID) {
        open.remove(window)
    }
}
