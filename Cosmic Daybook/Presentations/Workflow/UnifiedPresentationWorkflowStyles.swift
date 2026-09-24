import SwiftUI

// MARK: - Card Background Modifier

struct CardBackground: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat
    
    init(color: Color = Color.primary.opacity(UIConstants.OpacityConstants.whisper), cornerRadius: CGFloat = 12) {
        self.color = color
        self.cornerRadius = cornerRadius
    }
    
    func body(content: Content) -> some View {
        content.surface(
            cornerRadius,
            fill: color,
            style: .continuous
        )
    }
}

extension View {
    func cardBackground(
        color: Color = Color.primary.opacity(UIConstants.OpacityConstants.whisper),
        cornerRadius: CGFloat = 12
    ) -> some View {
        modifier(CardBackground(color: color, cornerRadius: cornerRadius))
    }
}

// MARK: - Animation Extensions

extension Animation {
    static let workflowSelection = Animation.spring(response: 0.3, dampingFraction: 0.7)
}

// MARK: - Font Extensions

extension Font {
    static let workflowFieldLabel = Font.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded)
    static let workflowCaption = Font.system(size: AppTheme.FontSize.caption, design: .rounded)
    static let workflowCallout = Font.system(size: AppTheme.FontSize.callout, weight: .medium, design: .rounded)
}
