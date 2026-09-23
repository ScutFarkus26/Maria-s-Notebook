import SwiftUI

/// A reusable pill-shaped status indicator with optional icon.
///
/// The one capsule badge: an optional symbol, a label, the status colour as
/// text and as a tint behind it. `Metrics` carries the sizes; the presets
/// are the four badges the app drew before 2026-09-22 (`StatusPill`,
/// `GoingOutStatusBadge`, `WorkflowBadge`, `SequenceRecapStateBadge`), each
/// reproduced exactly.
struct StatusPill: View {
    struct Metrics {
        var spacing: CGFloat = AppTheme.Spacing.verySmall
        var iconFont: Font = .system(size: UIConstants.CardSize.iconSize)
        var textFont: Font = AppTheme.ScaledFont.caption
        /// Applied after `textFont`; nil keeps the font's own weight.
        var textWeight: Font.Weight? = .medium
        var horizontalPadding: CGFloat = AppTheme.Spacing.sm
        var verticalPadding: CGFloat = AppTheme.Spacing.statusPillVertical
        var tintOpacity: Double = UIConstants.OpacityConstants.medium
        var capsuleStyle: RoundedCornerStyle = .circular

        /// 16 pt icon, footnote text — attendance, lesson and project status.
        static var standard: Metrics { Metrics() }

        /// 9 pt icon, caption2 semibold, 8 × 4, continuous — going-out status.
        static var compact: Metrics {
            var metrics = Metrics()
            metrics.spacing = 4
            metrics.iconFont = .system(size: 9)
            metrics.textFont = .caption2
            metrics.textWeight = .semibold
            metrics.horizontalPadding = 8
            metrics.verticalPadding = 4
            metrics.capsuleStyle = .continuous
            return metrics
        }

        /// 10 pt semibold icon, caption2 semibold, 10 × 6, tint 0.15 —
        /// work status and kind on the presentation workflow panel.
        static var emphasized: Metrics {
            var metrics = Metrics()
            metrics.spacing = 6
            metrics.iconFont = .system(size: 10, weight: .semibold)
            metrics.textFont = AppTheme.ScaledFont.captionSmallSemibold
            metrics.textWeight = nil
            metrics.horizontalPadding = 10
            metrics.verticalPadding = 6
            metrics.tintOpacity = UIConstants.OpacityConstants.accent
            return metrics
        }

        /// caption2 semibold, 6 × 2, tint 0.18 — a lesson's state on the
        /// sequence recap.
        static var mini: Metrics {
            var metrics = Metrics()
            metrics.textFont = AppTheme.ScaledFont.captionSmallSemibold
            metrics.textWeight = nil
            metrics.horizontalPadding = 6
            metrics.verticalPadding = 2
            metrics.tintOpacity = 0.18
            return metrics
        }
    }

    let text: String
    let color: Color
    let icon: String?
    let metrics: Metrics

    init(text: String, color: Color, icon: String? = nil, metrics: Metrics = .standard) {
        self.text = text
        self.color = color
        self.icon = icon
        self.metrics = metrics
    }

    var body: some View {
        HStack(spacing: metrics.spacing) {
            if let icon {
                Image(systemName: icon)
                    .font(metrics.iconFont)
            }
            Text(text)
                .font(metrics.textFont)
                .fontWeight(metrics.textWeight)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .capsuleFill(color.opacity(metrics.tintOpacity), style: metrics.capsuleStyle)
        .foregroundStyle(color)
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct StatusPillPreview: View {
    var body: some View {
        VStack(spacing: 16) {
            StatusPill(text: "Active", color: .green)
            StatusPill(text: "Pending", color: .orange, icon: "clock")
            StatusPill(text: "Complete", color: .blue, icon: "checkmark")
            StatusPill(text: "Proposed", color: .orange, icon: "clock", metrics: .compact)
            StatusPill(text: "Working", color: .blue, icon: "hammer", metrics: .emphasized)
            StatusPill(text: "Practicing", color: .blue, metrics: .mini)
        }
        .padding()
    }
}

#Preview {
    StatusPillPreview()
}
