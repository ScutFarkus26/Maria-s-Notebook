import SwiftUI

/// Backwards-compatible nav pill.
///
/// For new code, prefer `AppPillButton` directly.
struct PillNavButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        var metrics = AppPill.Metrics()
        metrics.font = .system(size: AppTheme.FontSize.body, weight: .semibold)
        metrics.horizontalPadding = 20
        metrics.verticalPadding = 8
        metrics.minHeight = 30

        // Use the same selection language as agenda pills (accent outline) to keep
        // pill appearance consistent across the app.
        return AppPillButton(title,
                             isSelected: isSelected,
                             selectionStyle: .accentOutline,
                             metrics: metrics,
                             action: action)
            .accessibilityLabel(Text(title))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 12) {
        PillNavButton(title: "Overview", isSelected: true) {}
        PillNavButton(title: "Checklist", isSelected: false) {}
    }
    .padding()
}
