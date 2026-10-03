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
        guard let openWindow else { return false }
        openWindow(id: Self.mainWindowID)
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
