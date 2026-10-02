// AttendanceClassSummaryCard.swift
// Sidebar card with class-wide attendance rate, on-time rate, and each one's
// change from the period before, in words.

import SwiftUI

struct AttendanceClassSummaryCard: View {
    let summary: AttendanceClassSummary
    let priorSummary: AttendanceClassSummary?
    let timeframeLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack {
                Text("Class Summary")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer()
                Text(timeframeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if summary.totalStudentDays == 0 {
                Text("No attendance recorded in this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AppTheme.Spacing.small)
            } else {
                metricsRow
                Text(summary.schoolDays == 1 ? "1 school day" : "\(summary.schoolDays) school days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(cardBackground)
    }

    // MARK: Metrics

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
            metric(
                label: "attended",
                value: summary.attendanceRate.map(percentString) ?? "—",
                trend: trend(current: summary.attendanceRate, prior: priorSummary?.attendanceRate),
                tint: .green
            )
            metric(
                label: "on time",
                value: summary.onTimeRate.map(percentString) ?? "—",
                trend: trend(current: summary.onTimeRate, prior: priorSummary?.onTimeRate),
                tint: .blue
            )
        }
    }

    private func metric(label: String, value: String, trend: AttendanceTrendDelta?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            // "▲ 1 pt vs prior 30d": the change in words, not just an arrow.
            if let trend {
                Text(trend.phrase(vs: timeframeLabel))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(trend.color)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.control, style: .continuous)
            .fill(Color.secondary.opacity(0.06))
    }

    // MARK: Helpers

    private func percentString(_ rate: Double) -> String {
        let pct = Int((rate * 100).rounded())
        return "\(pct)%"
    }

    private func trend(current: Double?, prior: Double?) -> AttendanceTrendDelta? {
        guard let current, let prior else { return nil }
        let delta = current - prior
        if abs(delta) < 0.005 { return AttendanceTrendDelta(direction: .flat, magnitude: 0) }
        return AttendanceTrendDelta(direction: delta > 0 ? .up : .down, magnitude: abs(delta))
    }
}

private struct AttendanceTrendDelta {
    enum Direction { case up, down, flat }
    let direction: Direction
    let magnitude: Double
    /// "▲ 1 pt vs prior 30d", "no change vs prior 30d".
    func phrase(vs timeframe: String) -> String {
        let points = Int((magnitude * 100).rounded())
        switch direction {
        case .flat: return "no change vs prior \(timeframe)"
        case .up: return "▲ \(points) pt vs prior \(timeframe)"
        case .down: return "▼ \(points) pt vs prior \(timeframe)"
        }
    }
    var color: Color {
        switch direction {
        case .up: return .green
        case .down: return .orange
        case .flat: return .secondary
        }
    }
}
