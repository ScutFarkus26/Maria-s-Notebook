import SwiftUI

/// A view modifier for applying consistent card background styling
struct CardBackgroundModifier: ViewModifier {
    let color: Color
    let opacity: Double
    let cornerRadius: CGFloat
    
    init(
        color: Color = .accentColor,
        opacity: Double = UIConstants.OpacityConstants.medium,
        cornerRadius: CGFloat = UIConstants.CornerRadius.large
    ) {
        self.color = color
        self.opacity = opacity
        self.cornerRadius = cornerRadius
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color.opacity(opacity))
            )
    }
}

extension View {
    /// Apply a consistent card background with rounded corners
    func cardBackground(
        color: Color = .accentColor,
        opacity: Double = UIConstants.OpacityConstants.medium,
        cornerRadius: CGFloat = UIConstants.CornerRadius.large
    ) -> some View {
        modifier(CardBackgroundModifier(color: color, opacity: opacity, cornerRadius: cornerRadius))
    }
}

#Preview {
    VStack(spacing: 16) {
        Text("Default Card")
            .padding()
            .cardBackground()
        
        Text("Custom Color")
            .padding()
            .cardBackground(color: .blue, opacity: 0.2)
        
        Text("Small Corner Radius")
            .padding()
            .cardBackground(cornerRadius: UIConstants.CornerRadius.small)
    }
    .padding()
}
