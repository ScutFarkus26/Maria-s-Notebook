import SwiftUI

extension DataManagementPanel {
    // MARK: - Result Banner

    func resultBanner(_ note: BackupResultNote) -> some View {
        let (symbol, color): (String, Color) = switch note.tone {
        case .success: (SFSymbol.Action.checkmarkCircleFill, AppColors.success)
        case .neutral: ("info.circle.fill", Color.secondary)
        case .failure: (SFSymbol.Status.exclamationmarkTriangleFill, AppColors.destructive)
        }
        return HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(note.text)
                .font(.caption)
                .lineLimit(note.tone == .failure ? nil : 1)
            Spacer()
            Button { resultMessage = nil } label: {
                Image(systemName: SFSymbol.Action.xmark)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, AppTheme.Spacing.small + 2)
        .padding(.vertical, AppTheme.Spacing.sm)
        .surface(
            AppTheme.Spacing.small,
            fill: color.opacity(UIConstants.OpacityConstants.medium),
            style: .continuous
        )
    }
}
