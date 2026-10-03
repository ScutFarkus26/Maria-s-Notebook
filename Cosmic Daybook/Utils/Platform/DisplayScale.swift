// DisplayScale.swift
// The screen scale for bitmaps rendered outside a view's environment.

import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Pixels per point for bitmaps sized before they reach a view (downsampled note
/// photos, attachment previews): the main screen's backing scale on the Mac, the
/// first window's trait scale on iOS (avoiding the deprecated `UIScreen.main`), and
/// 1 when there is neither.
enum DisplayScale {
    static var current: CGFloat {
        #if os(macOS)
        return NSScreen.main?.backingScaleFactor ?? 1.0
        #else
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.traitCollection.displayScale
        }
        return 1.0
        #endif
    }
}
