import SwiftUI

/// A ViewModifier that applies chip/pill styling with customizable colors and strokes
struct ChipModifier: ViewModifier {
    let backgroundColor: Color
    let strokeColor: Color?
    let strokeWidth: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    
    init(
        backgroundColor: Color,
        strokeColor: Color? = nil,
        strokeWidth: CGFloat = 1,
        horizontalPadding: CGFloat = AppTheme.Spacing.small,
        verticalPadding: CGFloat = AppTheme.Spacing.xxsmall
    ) {
        self.backgroundColor = backgroundColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                Capsule()
                    .fill(backgroundColor)
                    .overlay(
                        strokeColor.map { color in
                            Capsule().stroke(color, lineWidth: strokeWidth)
                        }
                    )
            )
    }
}

extension View {
    /// Applies chip/pill styling
    func chipStyle(
        backgroundColor: Color,
        strokeColor: Color? = nil,
        strokeWidth: CGFloat = 1,
        horizontalPadding: CGFloat = AppTheme.Spacing.small,
        verticalPadding: CGFloat = AppTheme.Spacing.xxsmall
    ) -> some View {
        modifier(ChipModifier(
            backgroundColor: backgroundColor,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        ))
    }
    
    /// Applies chip/pill styling with color and opacity
    func chipStyle(
        color: Color,
        opacity: Double = UIConstants.OpacityConstants.medium,
        strokeColor: Color? = nil
    ) -> some View {
        chipStyle(
            backgroundColor: color.opacity(opacity),
            strokeColor: strokeColor
        )
    }
}
