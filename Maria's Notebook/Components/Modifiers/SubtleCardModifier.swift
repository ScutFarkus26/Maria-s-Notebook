import SwiftUI

/// A ViewModifier that applies subtle card styling with optional stroke
struct SubtleCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let fillOpacity: Double
    let strokeOpacity: Double?
    let strokeWidth: CGFloat
    
    init(
        cornerRadius: CGFloat = UIConstants.CornerRadius.medium,
        fillOpacity: Double = UIConstants.OpacityConstants.veryFaint,
        strokeOpacity: Double? = UIConstants.OpacityConstants.subtle,
        strokeWidth: CGFloat = UIConstants.StrokeWidth.thin
    ) {
        self.cornerRadius = cornerRadius
        self.fillOpacity = fillOpacity
        self.strokeOpacity = strokeOpacity
        self.strokeWidth = strokeWidth
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.primary.opacity(fillOpacity))
                    .overlay(
                        strokeOpacity.map { opacity in
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(Color.primary.opacity(opacity), lineWidth: strokeWidth)
                        }
                    )
            )
    }
}

extension View {
    /// Applies subtle card styling
    func subtleCard(
        cornerRadius: CGFloat = UIConstants.CornerRadius.medium,
        fillOpacity: Double = UIConstants.OpacityConstants.veryFaint,
        strokeOpacity: Double? = UIConstants.OpacityConstants.subtle,
        strokeWidth: CGFloat = UIConstants.StrokeWidth.thin
    ) -> some View {
        modifier(SubtleCardModifier(
            cornerRadius: cornerRadius,
            fillOpacity: fillOpacity,
            strokeOpacity: strokeOpacity,
            strokeWidth: strokeWidth
        ))
    }
}
