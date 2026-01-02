import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared card styling utilities for consistent UI across the app.
enum CardStyle {
    /// Standard card background color (platform-adaptive)
    static var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
    
    /// Standard card corner radius
    static let cornerRadius: CGFloat = 12
    
    /// Standard card padding
    static let padding: CGFloat = 12
    
    /// Standard card stroke opacity
    static let strokeOpacity: Double = 0.06
    
    /// Standard card shadow
    static let shadowColor = Color.black.opacity(0.06)
    static let shadowRadius: CGFloat = 3
    static let shadowOffset = CGSize(width: 0, height: 1)
}

/// View modifier for applying standard card styling
struct CardStyleModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat
    
    init(cornerRadius: CGFloat = CardStyle.cornerRadius, padding: CGFloat = CardStyle.padding) {
        self.cornerRadius = cornerRadius
        self.padding = padding
    }
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(CardStyle.cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(CardStyle.strokeOpacity))
            )
            .shadow(
                color: CardStyle.shadowColor,
                radius: CardStyle.shadowRadius,
                x: CardStyle.shadowOffset.width,
                y: CardStyle.shadowOffset.height
            )
    }
}

extension View {
    /// Applies standard card styling to the view
    func cardStyle(cornerRadius: CGFloat = CardStyle.cornerRadius, padding: CGFloat = CardStyle.padding) -> some View {
        modifier(CardStyleModifier(cornerRadius: cornerRadius, padding: padding))
    }
}


