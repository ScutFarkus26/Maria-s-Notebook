#if os(macOS)

import AppKit

// Dummy UIKit symbols to allow UIKit-style scene activation calls to compile on macOS
public class UISceneSession {}

public enum UIScene {
    public class ActivationRequestOptions {}
}

extension NSApplication {
    /// No-op on AppKit; UIKit scene activation is not applicable on macOS.
    /// Prefer using SwiftUI's openWindow or managing NSWindowController directly instead.
    public func requestSceneSessionActivation(_ sceneSession: UISceneSession?,
                                              userActivity: NSUserActivity?,
                                              options: UIScene.ActivationRequestOptions?,
                                              errorHandler: ((Error) -> Void)? = nil) {
        // Intentionally left blank
    }
}

#endif
