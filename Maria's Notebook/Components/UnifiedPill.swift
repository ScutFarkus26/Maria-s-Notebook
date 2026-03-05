import SwiftUI

/// Canonical pill styling used throughout the app.
///
/// Design intent:
/// - Comfortable, capsule-shaped tap targets
/// - Neutral background by default
/// - Two common selection modes:
///   - `accentOutline`: subtle accent ring when selected (matches agenda pills)
///   - `accentFill`: filled accent background when selected (use sparingly for top-level nav)
enum AppPill {
    enum SelectionStyle {
        case accentOutline
        case accentFill
    }

    struct Metrics {
        var font: Font = .system(size: 12, weight: .semibold, design: .rounded)
        var horizontalPadding: CGFloat = 12
        var verticalPadding: CGFloat = 7
        var minHeight: CGFloat = 30
        var outlineWidth: CGFloat = 1
        var selectedRingWidth: CGFloat = 2
        var corner: Capsule = Capsule()
    }

    static func background(isSelected: Bool, selectionStyle: SelectionStyle) -> some ShapeStyle {
        switch selectionStyle {
        case .accentOutline:
            return AnyShapeStyle(Color.primary.opacity(0.06))
        case .accentFill:
            return AnyShapeStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
        }
    }

    static func foreground(isSelected: Bool, selectionStyle: SelectionStyle) -> some ShapeStyle {
        switch selectionStyle {
        case .accentOutline:
            return AnyShapeStyle(Color.primary)
        case .accentFill:
            return AnyShapeStyle(isSelected ? Color.white : Color.primary)
        }
    }
}

/// A reusable pill-shaped button.
struct AppPillButton<Label: View>: View {
    let isSelected: Bool
    let selectionStyle: AppPill.SelectionStyle
    let metrics: AppPill.Metrics
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(
        isSelected: Bool = false,
        selectionStyle: AppPill.SelectionStyle = .accentOutline,
        metrics: AppPill.Metrics = .init(),
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.isSelected = isSelected
        self.selectionStyle = selectionStyle
        self.metrics = metrics
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .font(metrics.font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(AppPill.foreground(isSelected: isSelected, selectionStyle: selectionStyle))
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
                .frame(minHeight: metrics.minHeight)
                .background(
                    metrics.corner
                        .fill(AppPill.background(isSelected: isSelected, selectionStyle: selectionStyle))
                )
                .overlay(
                    metrics.corner
                        .stroke(
                            Color.primary.opacity(
                                selectionStyle == .accentFill && isSelected ? 0.0 : 0.10
                            ),
                            lineWidth: metrics.outlineWidth
                        )
                )
                .overlay(
                    metrics.corner
                        .stroke(
                            Color.accentColor.opacity(
                                selectionStyle == .accentOutline && isSelected ? 0.45 : 0.0
                            ),
                            lineWidth: metrics.selectedRingWidth
                        )
                )
        }
        .buttonStyle(.plain)
        .contentShape(metrics.corner)
    }
}

extension AppPillButton where Label == Text {
    init(
        _ title: String,
        isSelected: Bool = false,
        selectionStyle: AppPill.SelectionStyle = .accentOutline,
        metrics: AppPill.Metrics = .init(),
        action: @escaping () -> Void
    ) {
        self.init(isSelected: isSelected, selectionStyle: selectionStyle, metrics: metrics, action: action) {
            Text(title)
        }
    }
}
