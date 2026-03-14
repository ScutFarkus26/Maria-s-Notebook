import SwiftUI

/// Reusable view modifiers for common styling patterns.
/// Reduces duplication and ensures consistent UI across the app.
extension View {
    /// Applies standard section header styling.
    /// - Returns: A view with section header styling applied
    func sectionHeaderStyle() -> some View {
        self
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
    
    /// Applies standard error message styling.
    /// - Returns: A view with error message styling applied
    func errorMessageStyle() -> some View {
        self
            .font(.caption)
            .foregroundStyle(AppColors.destructive)
            .padding(.horizontal)
    }
    
    /// Applies standard loading indicator styling.
    /// - Returns: A view with loading indicator styling applied
    func loadingStyle() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }
    
    /// Platform-adaptive background color for cards.
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
