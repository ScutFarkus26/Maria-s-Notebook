import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MakeNewWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Commands {
        #if os(macOS)
        // Adds a "New Window" menu item after the New Item section.
        // This replaces any legacy NSApplication.requestSceneSessionActivation usage.
        CommandGroup(after: .newItem) {
            Button("New Window") {
                openWindow(id: "MainWindow")
            }
            .keyboardShortcut("N", modifiers: [.command, .shift])
        }
        #endif
    }
}
