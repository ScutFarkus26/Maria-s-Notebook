// AttendanceWatchListCard.swift
// Sidebar card listing students with the highest absence/tardy counts in the timeframe.

import SwiftUI

struct AttendanceWatchListCard: View {
    let entries: [AttendanceWatchListEntry]
    let timeframeLabel: String
    let onSelectStudent: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack {
                Text("Students to Watch")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer()
                Text(timeframeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if entries.isEmpty {
                Text("No concerning patterns this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AppTheme.Spacing.small)
            } else {
                VStack(spacing: AppTheme.Spacing.small) {
                    ForEach(entries) { entry in
                        Button {
                            onSelectStudent(entry.studentID)
                        } label: {
                            row(for: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(cardBackground)
    }

    private func row(for entry: AttendanceWatchListEntry) -> some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fullName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                statsLine(absent: entry.absentCount, tardy: entry.tardyCount)
                patternStrip(pattern: entry.recentPattern)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func statsLine(absent: Int, tardy: Int) -> some View {
        HStack(spacing: 6) {
            if absent > 0 {
                Text("\(absent) absent")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            if absent > 0 && tardy > 0 {
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if tardy > 0 {
                Text("\(tardy) tardy")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
    }

    private func patternStrip(pattern: [AttendanceStatus]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(pattern.enumerated()), id: \.offset) { _, status in
                Circle()
                    .fill(dotColor(for: status))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.top, 2)
    }

    private func dotColor(for status: AttendanceStatus) -> Color {
        switch status {
        case .present: return .green.opacity(0.85)
        case .absent: return .red.opacity(0.85)
        case .tardy: return .blue.opacity(0.85)
        case .leftEarly: return .purple.opacity(0.85)
        case .unmarked: return .secondary.opacity(0.25)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.secondary.opacity(0.06))
    }
}
