// View+PlatformStyles.swift
// Platform-specific view modifiers for consistent appearance

import SwiftUI

extension View {
    /// Adds a platform-appropriate separator border.
    func borderSeparated() -> some View {
        #if os(macOS)
        self.border(Color(nsColor: .separatorColor).opacity(UIConstants.OpacityConstants.half), width: 0.5)
        #else
        self.border(Color.gray.opacity(UIConstants.OpacityConstants.semi), width: 0.5)
        #endif
    }

    /// Applies a platform-appropriate background color for controls/cells.
    func backgroundPlatform() -> some View {
        #if os(macOS)
        self.background(Color(nsColor: .controlBackgroundColor))
        #else
        self.background(Color(uiColor: .secondarySystemBackground))
        #endif
    }
}

// MARK: - Platform Colors

extension Color {
    /// Returns platform-appropriate control background color (appears 32+ times in codebase)
    static func controlBackgroundColor(opacity: Double = 1.0) -> Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor).opacity(opacity)
        #else
        return Color(uiColor: .secondarySystemBackground).opacity(opacity)
        #endif
    }
    
    /// Returns platform-appropriate window/system background color (appears 14+ times in codebase)
    static func windowBackgroundColor(opacity: Double = 1.0) -> Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor).opacity(opacity)
        #else
        return Color(uiColor: .systemBackground).opacity(opacity)
        #endif
    }
}

// MARK: - Navigation Bar

extension View {
    /// Applies inline navigation bar title display mode on iOS, no-op on macOS.
    func inlineNavigationTitle() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Sheet Presentation Sizing

/// Sheet sizing options for platform-appropriate presentation
enum SheetSize {
    case small       // 400×300 macOS, medium iOS
    case medium      // 500×400 macOS, medium/large iOS
    case large       // 600×500 macOS, large iOS
    case custom(minWidth: CGFloat, minHeight: CGFloat)
}
