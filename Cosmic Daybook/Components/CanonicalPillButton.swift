import SwiftUI

/// Backwards-compatible wrapper for the app's canonical pill implementation.
///
/// Use `AppPillButton` for new code. This type remains so existing views compile
/// without requiring call-site edits.
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
        var metrics = AppPill.Metrics()
        metrics.font = contentFont ?? metrics.font
        metrics.horizontalPadding = horizontalPadding
        metrics.verticalPadding = verticalPadding
        return AppPillButton(
            isSelected: isSelected,
            selectionStyle: .accentOutline,
            metrics: metrics,
            action: action,
            label: content
        )
    }
}

extension CanonicalPillButton where Content == Text {
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
