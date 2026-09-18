import SwiftUI

/// A small pill showing the AI model icon and display name.
/// Reused on message bubbles, empty state, and streaming indicator.
struct ModelBadgeView: View {
    let model: AIModelOption
    let style: BadgeStyle

    enum BadgeStyle {
        /// Small badge used below assistant messages (caption2 size)
        case compact
        /// Medium badge used in the empty state ("Powered by...")
        case standard
        /// Inline badge used in the toolbar
        case toolbar
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: model.iconName)
                .font(font)
            Text(displayText)
                .font(font)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(background)
        .clipShape(Capsule())
    }

    // MARK: - Style Variants

    private var font: Font {
        switch style {
        case .compact: AppTheme.ScaledFont.captionSmall
        case .standard: AppTheme.ScaledFont.caption
        case .toolbar: AppTheme.ScaledFont.captionSmall
        }
    }

    private var displayText: String {
        switch style {
        case .compact: model.displayName
        case .standard: "Powered by \(model.displayName)"
        case .toolbar: model.displayName
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .compact: .secondary
        case .standard: .secondary
        case .toolbar: .accentColor
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .compact: AppTheme.Spacing.verySmall   // 6pt
        case .standard: AppTheme.Spacing.small       // 8pt
        case .toolbar: AppTheme.Spacing.verySmall    // 6pt
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .compact: AppTheme.Spacing.xxsmall      // 2pt
        case .standard: AppTheme.Spacing.xsmall      // 4pt
        case .toolbar: AppTheme.Spacing.xxsmall      // 2pt
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .compact:
            Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint)   // 0.06
        case .standard:
            Color.accentColor.opacity(UIConstants.OpacityConstants.light)     // 0.1
        case .toolbar:
            Color.accentColor.opacity(UIConstants.OpacityConstants.veryFaint) // 0.06
        }
    }
}
