import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension Color {
    /// Late's color: amber, dark enough to read as text on a light bar and
    /// the system orange in dark mode.
    #if canImport(UIKit)
    static let lateAmber = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemOrange
            : UIColor(red: 0.74, green: 0.40, blue: 0.0, alpha: 1)
    })
    #else
    static let lateAmber = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .systemOrange
            : NSColor(red: 0.74, green: 0.40, blue: 0.0, alpha: 1)
    })
    #endif
}
