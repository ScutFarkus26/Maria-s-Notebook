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
//  does — so `MainWindowOpenerCommands` hands the action over whenever SwiftUI
//  evaluates the app's commands. On macOS 27 it builds the menu bar without
//  ever evaluating that body while no window is open (2026-11-03), so the
//  main window is then opened the way File ▸ New Window opens it: by
//  performing SwiftUI's own menu item, which does carry a live action.
//

#if os(macOS)
import OSLog
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

    /// Opens a new main window, as File > New Window does: through the
    /// captured `openWindow` when SwiftUI has handed one over, else by
    /// performing the File ▸ New Window menu item itself. False only when
    /// neither is there, so nothing could be opened.
    func openMainWindow() -> Bool {
        if open(id: Self.mainWindowID) {
            Logger.mcpServer.notice("Main window opened through the captured openWindow")
            return true
        }
        guard let (menu, index) = Self.newWindowMenuItem() else {
            let menus = Self.menuSummary()
            Logger.mcpServer.error(
                "Couldn't open the main window: no openWindow action, no New Window item.\n\(menus, privacy: .public)"
            )
            return false
        }
        // SwiftUI fills its items in when the menu is about to open; a
        // programmatic perform gets no such moment, so update the menu first.
        menu.update()
        menu.performActionForItem(at: index)
        Logger.mcpServer.notice("Main window opened through the File ▸ New Window item")
        return true
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

    /// SwiftUI's File ▸ New Window item in the app's menu bar. By its title
    /// first; failing that, the first File item that carries an action of
    /// its own with a target (SwiftUI's callback object): Close and Close All
    /// go through the responder chain with no target, and the app's own
    /// commands (New Lesson… is ⌘N too, so the shortcut tells them apart from
    /// nothing) carry no AppKit action while no window is open.
    private static func newWindowMenuItem() -> (NSMenu, Int)? {
        let menus = NSApplication.shared.mainMenu?.items.compactMap(\.submenu) ?? []
        for menu in menus {
            if let index = menu.items.firstIndex(where: { $0.title == "New Window" && $0.action != nil }) {
                return (menu, index)
            }
        }
        guard let fileMenu = menus.first(where: { $0.title == "File" })
            ?? menus.first(where: { menu in
                menu.items.contains { $0.action == #selector(NSWindow.performClose(_:)) }
            }),
              let index = fileMenu.items.firstIndex(where: { $0.action != nil && $0.target != nil })
        else { return nil }
        return (fileMenu, index)
    }

    /// What the menu bar holds, for the log when no New Window item is found.
    private static func menuSummary() -> String {
        (NSApplication.shared.mainMenu?.items ?? []).map { top in
            let items = (top.submenu?.items ?? []).filter { !$0.isSeparatorItem }.map { item in
                "\(item.title) key=\(item.keyEquivalent) mask=\(item.keyEquivalentModifierMask.rawValue) "
                    + "action=\(item.action.map(NSStringFromSelector) ?? "nil") "
                    + "target=\(item.target == nil ? "nil" : "set")"
            }
            return "\(top.title): [" + items.joined(separator: "; ") + "]"
        }.joined(separator: "\n")
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
