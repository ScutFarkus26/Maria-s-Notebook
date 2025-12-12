import SwiftUI

/// Canonical pill button used across the app, matching the Lessons Agenda neutral pill style.
/// Visual characteristics:
/// - Neutral very-light fill, subtle 1pt outline
/// - Optional accent outline when selected/active
/// - Semibold rounded text by default (overridable)
/// - Comfortable insets by default (overridable)
struct CanonicalPillButton<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    let content: () -> Content
    let contentFont: Font?
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(
        isSelected: Bool = false,
        contentFont: Font? = nil,
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 6,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isSelected = isSelected
        self.contentFont = contentFont
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            content()
                .font(contentFont ?? .system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.accentColor.opacity(isSelected ? 0.45 : 0.0), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}

extension CanonicalPillButton where Content == Text {
    /// Convenience init for simple text labels.
    init(
        _ title: String,
        isSelected: Bool = false,
        contentFont: Font? = nil,
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 6,
        action: @escaping () -> Void
    ) {
        self.init(
            isSelected: isSelected,
            contentFont: contentFont,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            action: action
        ) {
            Text(title)
        }
    }
}
