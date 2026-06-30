//  Color+Adaptive.swift
//  Maria's Notebook
//
//  Builds appearance-adaptive colors so custom brand/status accents resolve
//  differently in Light vs Dark Mode — the way the system colors (.red, .orange,
//  …) already do. Use this for any semantic color that would otherwise be a
//  single fixed sRGB value and therefore look muddy on a dark background.

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// A color that resolves to `light` in the Light appearance and `dark` in the
    /// Dark appearance. Backed by the platform's dynamic color, so it also tracks
    /// the user's appearance changes at runtime.
    init(light: Color, dark: Color) {
        #if os(macOS)
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
        #else
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
    }
}
