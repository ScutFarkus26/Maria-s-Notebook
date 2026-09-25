// AttendanceLogView+Summary.swift
// The counts strip above the attendance log.

import SwiftUI

extension AttendanceLogView {

    // MARK: - Summary Stats View

    /// `stats` is computed once per render from the filtered records.
    func summaryStatsView(_ stats: AttendanceSummary) -> some View {
        HStack(spacing: 16) {
            statBadge(count: stats.present, label: "Present", color: .green)
            statBadge(count: stats.absent, label: "Absent", color: .red)
            statBadge(count: stats.tardy, label: "Tardy", color: .blue)
            statBadge(count: stats.leftEarly, label: "Left Early", color: .purple)
            Spacer()
            Text("\(stats.total) records")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.ghost))
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(UIConstants.OpacityConstants.statusBg))
                .frame(width: 10, height: 10)
            Text("\(count)")
                .font(AppTheme.ScaledFont.bodySemibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
