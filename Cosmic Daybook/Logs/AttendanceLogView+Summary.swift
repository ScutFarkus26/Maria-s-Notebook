// AttendanceLogView+Summary.swift
// The counts strip above the attendance log.

import SwiftUI

extension AttendanceLogView {

    // MARK: - Summary Stats View

    var summaryStatsView: some View {
        HStack(spacing: 16) {
            statBadge(count: summaryStats.present, label: "Present", color: .green)
            statBadge(count: summaryStats.absent, label: "Absent", color: .red)
            statBadge(count: summaryStats.tardy, label: "Tardy", color: .blue)
            statBadge(count: summaryStats.leftEarly, label: "Left Early", color: .purple)
            Spacer()
            Text("\(summaryStats.total) records")
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
