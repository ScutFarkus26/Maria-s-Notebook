// QuickPracticeSessionSheet+QualityMetrics.swift
// Quality metrics section extracted from QuickPracticeSessionSheet

import SwiftUI

extension QuickPracticeSessionSheet {
    // MARK: - Quality Metrics Section

    var qualityMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quality Metrics")
                .font(AppTheme.ScaledFont.calloutSemibold)

            // Practice Quality
            VStack(alignment: .leading, spacing: 8) {
                Text("Practice Quality")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        qualityCircle(level: level, selected: practiceQuality, color: .blue) {
                            practiceQuality = level
                        }
                    }

                    Spacer()

                    if let quality = practiceQuality {
                        Text(qualityLabel(for: quality))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Independence Level
            VStack(alignment: .leading, spacing: 8) {
                Text("Independence Level")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        qualityCircle(level: level, selected: independenceLevel, color: .green) {
                            independenceLevel = level
                        }
                    }

                    Spacer()

                    if let independence = independenceLevel {
                        Text(independenceLabel(for: independence))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    func qualityCircle(level: Int, selected: Int?, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color.opacity((selected ?? 0) >= level ? 1.0 : 0.2))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Functions

    func qualityLabel(for level: Int) -> String {
        switch level {
        case 1: return "Distracted"
        case 2: return "Minimal"
        case 3: return "Adequate"
        case 4: return "Good"
        case 5: return "Excellent"
        default: return ""
        }
    }

    func independenceLabel(for level: Int) -> String {
        switch level {
        case 1: return "Constant Help"
        case 2: return "Frequent Guidance"
        case 3: return "Some Support"
        case 4: return "Mostly Independent"
        case 5: return "Fully Independent"
        default: return ""
        }
    }
}
