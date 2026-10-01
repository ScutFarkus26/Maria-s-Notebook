import SwiftUI

/// One choice on the presentation sheet: a decision for a child or the group,
/// or a check-in day.
///
/// Four looks keep "everyone" and "only this child" apart at a glance: the
/// group's choice is solid, a child inheriting it is a dashed tint, and a child
/// who differs is solid in a second color.
struct PresentationDecisionChip: View {
    enum Look {
        case plain
        case chosen
        case inherited
        case differs
    }

    /// The color for a child whose decision differs from everyone's.
    static let differsColor = Color(red: 0.66, green: 0.33, blue: 0.04)

    let title: String
    let look: Look
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.ScaledFont.callout.weight(look == .plain ? .regular : .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(minHeight: chipHeight)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        border,
                        style: StrokeStyle(lineWidth: 1, dash: look == .inherited ? [4, 3] : [])
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(look == .plain ? [] : .isSelected)
    }

    private var chipHeight: CGFloat {
        #if os(iOS)
        36
        #else
        28
        #endif
    }

    private var foreground: Color {
        switch look {
        case .plain: .primary
        case .chosen, .differs: .white
        case .inherited: .accentColor
        }
    }

    private var background: Color {
        switch look {
        case .plain: Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
        case .chosen: .accentColor
        case .inherited: Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
        case .differs: Self.differsColor
        }
    }

    private var border: Color {
        switch look {
        case .plain: Color.primary.opacity(UIConstants.OpacityConstants.light)
        case .chosen: .accentColor
        case .inherited: Color.accentColor.opacity(UIConstants.OpacityConstants.semi)
        case .differs: Self.differsColor
        }
    }
}
