import SwiftUI

/// A reusable pill-shaped status indicator with optional icon
struct StatusPill: View {
    let text: String
    let color: Color
    let icon: String?
    
    init(text: String, color: Color, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.verySmall) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: UIConstants.CardSize.iconSize))
            }
            Text(text)
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.statusPillVertical)
        .background(
            Capsule()
                .fill(color.opacity(UIConstants.OpacityConstants.medium))
        )
        .foregroundStyle(color)
    }
}

#Preview {
    VStack(spacing: 16) {
        StatusPill(text: "Active", color: .green)
        StatusPill(text: "Pending", color: .orange, icon: "clock")
        StatusPill(text: "Complete", color: .blue, icon: "checkmark")
    }
    .padding()
}
