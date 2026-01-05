#if os(macOS)
import SwiftUI

/// View modifier that listens for openNewWindow notifications and opens a new window
struct OpenWindowOnNotificationModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openNewWindow)) { _ in
                openWindow(id: "mainWindow")
            }
    }
}
#endif

