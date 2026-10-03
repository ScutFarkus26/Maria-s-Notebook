#if os(iOS)
import UIKit
#endif

/// Device questions a screen's wording depends on.
enum PlatformIdiom {
    /// True on an iPhone, where dragging a PDF or a link in from another app
    /// isn't how anyone adds one, so instructions that say "drag" read wrong.
    static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
}
