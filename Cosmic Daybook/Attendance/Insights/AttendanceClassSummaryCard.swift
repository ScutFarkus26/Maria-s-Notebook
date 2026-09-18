// AttendanceClassSummaryCard.swift
// Sidebar card with class-wide attendance rate, on-time rate, and a trend delta.

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
                divider
                breakdownRow
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(cardBackground)
    }

    // MARK: Metrics

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
            metric(
                label: "Attendance",
                value: summary.attendanceRate.map(percentString) ?? "—",
                trend: trend(current: summary.attendanceRate, prior: priorSummary?.attendanceRate),
                tint: .green
            )
            metric(
                label: "On-time",
                value: summary.onTimeRate.map(percentString) ?? "—",
                trend: trend(current: summary.onTimeRate, prior: priorSummary?.onTimeRate),
                tint: .blue
            )
        }
    }

    private func metric(label: String, value: String, trend: AttendanceTrendDelta?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(tint)
                if let trend {
                    Image(systemName: trend.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(trend.color)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(height: 1)
    }

    // MARK: Breakdown

    private var breakdownRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            chip(label: "Present", count: summary.presentCount, color: .green)
            chip(label: "Tardy", count: summary.tardyCount, color: .blue)
            chip(label: "Absent", count: summary.absentCount, color: .red)
            if summary.leftEarlyCount > 0 {
                chip(label: "Left Early", count: summary.leftEarlyCount, color: .purple)
            }
            HStack(spacing: 4) {
                Text("\(summary.schoolDays)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(summary.schoolDays == 1 ? "school day tracked" : "school days tracked")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }

    private func chip(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
    var icon: String {
        switch direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
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
