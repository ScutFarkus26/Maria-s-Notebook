import SwiftUI

// MARK: - Settings Empty State

/// A small, warm empty state for a Settings list with nothing in it, such as a sprout
/// over "Nothing carried over". The symbol settles in once when the view first appears
/// (instantly under Reduce Motion) and then stays still.
struct SettingsEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = AppColors.success

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .scaleEffect(hasAppeared ? 1 : 0.6, anchor: .bottom)
                .opacity(hasAppeared ? 1 : 0)
                .padding(.bottom, AppTheme.Spacing.xsmall)
            Text(title)
                .font(AppTheme.ScaledFont.titleSmall)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.large)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.spring(duration: 0.6, bounce: 0.35)) {
                    hasAppeared = true
                }
            }
        }
    }
}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct SettingsEmptyStatePreview: View {
    var body: some View {
        SettingsEmptyState(
            symbol: "leaf.fill",
            title: "Nothing carried over",
            message: "Every planned year-plan target on the roster falls in this school year."
        )
        .frame(maxWidth: 420)
    }
}

#Preview {
    SettingsEmptyStatePreview()
}
