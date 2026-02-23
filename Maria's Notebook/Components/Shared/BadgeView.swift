import SwiftUI

/// A reusable badge/chip component with count or text
/// Standardizes badge patterns across the app
struct BadgeView: View {
    let text: String
    let color: Color
    let style: BadgeStyle
    
    enum BadgeStyle {
        case filled
        case outline
        case subtle
    }
    
    init(_ text: String, color: Color = .accentColor, style: BadgeStyle = .subtle) {
        self.text = text
        self.color = color
        self.style = style
    }
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.xxsmall)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(strokeColor, lineWidth: style == .outline ? UIConstants.StrokeWidth.thin : 0)
            )
    }
    
    private var backgroundColor: Color {
        switch style {
        case .filled:
            return color
        case .outline:
            return .clear
        case .subtle:
            return color.opacity(UIConstants.OpacityConstants.medium)
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .filled:
            return .white
        case .outline, .subtle:
            return color
        }
    }
    
    private var strokeColor: Color {
        style == .outline ? color : .clear
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            BadgeView("5", color: .blue, style: .filled)
            BadgeView("New", color: .green, style: .filled)
            BadgeView("Beta", color: .orange, style: .filled)
        }
        
        HStack(spacing: 12) {
            BadgeView("10", color: .purple, style: .outline)
            BadgeView("Pro", color: .red, style: .outline)
            BadgeView("Draft", color: .gray, style: .outline)
        }
        
        HStack(spacing: 12) {
            BadgeView("3", color: .blue)
            BadgeView("Active", color: .green)
            BadgeView("Pending", color: .orange)
        }
    }
    .padding()
}
