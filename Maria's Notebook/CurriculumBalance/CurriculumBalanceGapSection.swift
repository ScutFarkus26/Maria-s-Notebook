// CurriculumBalanceGapSection.swift
// Gap analysis display showing subjects with notably low representation.
// Design follows TodoAnalyticsView insights section: warning-tinted card with indicators.

import SwiftUI

struct CurriculumBalanceGapSection: View {
    let gaps: [SubjectGap]
    var onGapTapped: ((SubjectGap) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gap Analysis", systemImage: "exclamationmark.triangle.fill")
                .font(AppTheme.ScaledFont.calloutSemibold)
                .foregroundStyle(gaps.isEmpty ? AppColors.success : AppColors.warning)

            if gaps.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                        .foregroundStyle(AppColors.success)
                    Text("Balanced coverage — no significant gaps detected")
                        .font(AppTheme.ScaledFont.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("These subjects are below 50% of the average lesson count:")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)

                    ForEach(gaps) { gap in
                        gapRow(gap)
                    }
                }
            }
        }
        .padding()
        .background(
            (gaps.isEmpty ? AppColors.success : AppColors.warning).opacity(UIConstants.OpacityConstants.light)
        )
        .cornerRadius(UIConstants.CornerRadius.large)
    }

    private func gapRow(_ gap: SubjectGap) -> some View {
        Button {
            onGapTapped?(gap)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(gap.color)
                    .frame(width: 8, height: 8)

                Text(gap.subject)
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.primary)

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(gap.count) lessons")
                        .font(AppTheme.ScaledFont.captionSmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.warning)

                    Text("avg \(String(format: "%.0f", gap.classAverage))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if onGapTapped != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small, style: .continuous)
                    .fill(onGapTapped != nil ? Color.primary.opacity(UIConstants.OpacityConstants.veryFaint) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
