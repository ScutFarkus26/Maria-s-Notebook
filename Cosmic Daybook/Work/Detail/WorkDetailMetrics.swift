import SwiftUI

// MARK: - Metric Components

struct MetricStatBox: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)

                Text(value)
                    .font(AppTheme.ScaledFont.header)
                    .foregroundStyle(.primary)
            }

            Text(label)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surface(UIConstants.CornerRadius.large, fill: color.opacity(UIConstants.OpacityConstants.subtle))
    }
}

struct QualityMetricBox: View {
    let level: Double
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)

                Text(String(format: "%.1f", level))
                    .font(AppTheme.ScaledFont.header)
                    .foregroundStyle(.primary)

                Text("/ 5")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surface(UIConstants.CornerRadius.large, fill: color.opacity(UIConstants.OpacityConstants.subtle))
    }
}

struct BehaviorPill: View {
    let behavior: String

    var body: some View {
        Text(behavior)
            .font(AppTheme.ScaledFont.captionSemibold)
            .foregroundStyle(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .capsuleFill(Color.blue.opacity(UIConstants.OpacityConstants.medium))
    }
}

struct FlagRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)

            Text(text)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(UIConstants.CornerRadius.medium, fill: color.opacity(UIConstants.OpacityConstants.subtle))
    }
}
