import SwiftUI

/// Shown in Settings → iCloud Sync when a mirroring delegate failed this
/// session: which part stopped and the fix that fits, in plain words, with
/// what the server said under Details (see `SyncStoppedAdvice`).
struct SyncStoppedBanner: View {
    let advice: SyncStoppedAdvice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.title3)
                .foregroundStyle(AppColors.destructive)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Text(advice.title)
                    .font(.subheadline.weight(.semibold))
                Text(advice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                TechnicalDetailsDisclosure(details: advice.details)
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.compact)
        .surface(
            UIConstants.CornerRadius.control,
            fill: AppColors.destructive.opacity(UIConstants.OpacityConstants.medium),
            stroke: AppColors.destructive.opacity(UIConstants.OpacityConstants.muted),
            lineWidth: 1,
            style: .continuous
        )
    }
}
