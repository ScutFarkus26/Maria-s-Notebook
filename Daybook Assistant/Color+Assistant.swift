import SwiftUI
import UIKit

extension Color {
    /// Late's color: amber, dark enough to read as text on the light bar and
    /// the system orange in dark mode.
    static let lateAmber = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemOrange
            : UIColor(red: 0.74, green: 0.40, blue: 0.0, alpha: 1)
    })
}
