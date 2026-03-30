import SwiftUI

struct MTSummaryStat: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let tint: Color
    let progress: Double? // Optional 0.0 ... 1.0
}

struct MTSummaryStrip: View {
    let stats: [MTSummaryStat]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(stats) { stat in
                    StatCard(stat: stat)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
    }

    private struct StatCard: View {
        let stat: MTSummaryStat

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(stat.icon)
                        .font(AppTheme.ScaledFont.titleSmall)
                        .accessibilityHidden(true)
                    Text(stat.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(stat.value)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)

                if let progress = stat.progress {
                    ProgressView(value: progress)
                        .tint(stat.tint)
                        .progressViewStyle(.linear)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(stat.tint.opacity(UIConstants.OpacityConstants.quarter), lineWidth: 1)
                    )
            )
            .shadow(color: stat.tint.opacity(UIConstants.OpacityConstants.accent), radius: 6, x: 0, y: 3)
            .frame(width: 180, alignment: .leading)
            .accessibilityLabel("\(stat.title), \(stat.value)")
        }
    }
}

#Preview {
    MTSummaryStrip(stats: [
        MTSummaryStat(title: "Records", value: "12,480", icon: "📦", tint: .blue, progress: nil),
        MTSummaryStat(title: "Storage", value: "245 MB", icon: "💾", tint: .purple, progress: 0.62),
        MTSummaryStat(title: "Last Sync", value: "2h ago", icon: "🔄", tint: .green, progress: nil),
        MTSummaryStat(title: "Errors", value: "0", icon: "✅", tint: .teal, progress: 1.0)
    ])
    .frame(maxWidth: CGFloat.infinity, maxHeight: 140)
}
