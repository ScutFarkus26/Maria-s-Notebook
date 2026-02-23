import SwiftUI

/// A reusable pill-shaped icon button with background
struct IconPill: View {
    let icon: String
    let color: Color
    let size: CGFloat
    
    init(icon: String, color: Color = .accentColor, size: CGFloat = UIConstants.CardSize.iconSize) {
        self.icon = icon
        self.color = color
        self.size = size
    }
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size))
            .foregroundStyle(color)
            .frame(width: size + AppTheme.Spacing.small, height: size + AppTheme.Spacing.small)
            .background(
                Capsule()
                    .fill(color.opacity(UIConstants.OpacityConstants.medium))
            )
    }
}

#Preview {
    HStack(spacing: 16) {
        IconPill(icon: "star.fill", color: .yellow)
        IconPill(icon: "heart.fill", color: .red, size: UIConstants.CardSize.iconSizeLarge)
        IconPill(icon: "checkmark", color: .green)
    }
    .padding()
}
