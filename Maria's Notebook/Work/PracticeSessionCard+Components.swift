import SwiftUI

// MARK: - Shared Helper Components

extension PracticeSessionCard {

    @ViewBuilder
    func qualityIndicator(level: Int, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { index in
                Circle()
                    .fill(color.opacity(level >= index ? 1.0 : 0.2))
                    .frame(width: 6, height: 6)
            }
            Text(label)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func behaviorTag(_ behavior: String) -> some View {
        Text(behavior)
            .font(AppTheme.ScaledFont.captionSemibold)
            .foregroundStyle(behaviorColor(for: behavior))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(behaviorColor(for: behavior).opacity(UIConstants.OpacityConstants.accent))
            )
    }

    func behaviorColor(for behavior: String) -> Color {
        switch behavior {
        case "Breakthrough!": return .green
        case "Struggled": return .orange
        case "Needs reteaching": return .red
        case "Ready for check-in", "Ready for assessment": return .blue
        case "Asked for help": return .purple
        case "Helped peer": return .teal
        default: return .gray
        }
    }

    @ViewBuilder
    func actionRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
            Text(text)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.primary)
        }
    }
}
