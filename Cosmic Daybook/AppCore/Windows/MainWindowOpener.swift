//
//  MainWindowOpener.swift
//  Cosmic Daybook
//
//  Lets AppKit code open the main window. An MCP-only launch suppresses the
//  main window scene at launch, and SwiftUI also consults that launch
//  behavior when the Dock icon is clicked with no window open, so it would
//  present nothing; the app delegate opens the window itself instead.
//  SwiftUI's `openWindow` lives in the environment, which only views and
//  commands can read, and the menu bar's commands exist even when no window
//  does — so `MainWindowOpenerCommands` hands the action over whenever the
//  menu bar is built.
//

#if os(macOS)
import SwiftUI

@MainActor
final class MainWindowOpener {
    static let shared = MainWindowOpener()

    /// The main window scene's id in `CosmicDaybookApp`.
    static let mainWindowID = "mainWindow"

    private var openWindow: OpenWindowAction?

    private init() {}

    func setAction(_ action: OpenWindowAction) {
        openWindow = action
    }

    /// Opens a new main window, as File > New Window does. Returns false when
    /// SwiftUI has not built the menu bar yet, so there is no action to call.
    func openMainWindow() -> Bool {
        open(id: Self.mainWindowID)
    }

    /// Opens the window scene `id` (Keyboard Shortcuts), whether or not a main
    /// window is open. False when there is no action yet, as for `openMainWindow`.
    func open(id: String) -> Bool {
        guard let openWindow else { return false }
        openWindow(id: id)
        return true
    }

    /// Opens `value` in the window scene `id`, or brings its window forward,
    /// whether or not a main window is open: the "open in new window" items
    /// work from a detail window too (bug hunt 2026-10-17 #36).
    func open<Value: Codable & Hashable>(id: String, value: Value) -> Bool {
        guard let openWindow else { return false }
        openWindow(id: id, value: value)
        return true
    }
}

/// Adds no menu items; it only passes the environment's `openWindow` to
/// `MainWindowOpener` each time SwiftUI evaluates the app's commands.
struct MainWindowOpenerCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // swiftlint:disable:next redundant_discardable_let
        let _ = MainWindowOpener.shared.setAction(openWindow)
        EmptyCommands()
    }
}
#endif
