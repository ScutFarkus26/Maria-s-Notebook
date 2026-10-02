// AttendanceWatchListCard.swift
// Sidebar card: Patterns, the children with the most absences and late
// arrivals, siblings gathered into their family.

import SwiftUI

struct AttendanceWatchListCard: View {
    let patterns: [AttendancePattern]
    let timeframeLabel: String
    let onSelectStudent: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack {
                Text("Patterns")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer()
                Text(timeframeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if patterns.isEmpty {
                Text("No absences or late arrivals this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AppTheme.Spacing.small)
            } else {
                VStack(spacing: AppTheme.Spacing.small) {
                    ForEach(patterns) { pattern in
                        if let family = pattern.familyName {
                            familyBlock(family, pattern)
                        } else if let child = pattern.members.first {
                            childRow(child, showsName: true)
                        }
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(cardBackground)
    }

    /// "Fleischmann family (4) · 15 late · 3 absent", then each child.
    private func familyBlock(_ family: String, _ pattern: AttendancePattern) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(family) family")
                    .font(.callout.weight(.semibold))
                Text("(\(pattern.members.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                statsLine(absent: pattern.absentCount, tardy: pattern.tardyCount)
            }
            Text("Siblings: one conversation with the family covers them all.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(pattern.members) { child in
                childRow(child, showsName: false)
            }
        }
        .padding(10)
        .background(Color.lateAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(family) family")
    }

    /// One child: the name and counts, and the last ten school days as dots.
    /// Opens the child's attendance history.
    private func childRow(_ entry: AttendanceWatchListEntry, showsName: Bool) -> some View {
        Button {
            onSelectStudent(entry.studentID)
        } label: {
            HStack(alignment: .center, spacing: AppTheme.Spacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(showsName ? entry.fullName : firstName(entry.fullName))
                            .font(showsName ? .callout.weight(.medium) : .caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !showsName {
                            Spacer(minLength: 4)
                            statsLine(absent: entry.absentCount, tardy: entry.tardyCount)
                        }
                    }
                    if showsName { statsLine(absent: entry.absentCount, tardy: entry.tardyCount) }
                    patternStrip(pattern: entry.recentPattern)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Attendance history")
    }

    private func firstName(_ fullName: String) -> String {
        fullName.components(separatedBy: " ").first ?? fullName
    }

    private func statsLine(absent: Int, tardy: Int) -> some View {
        Text([
            tardy > 0 ? "\(tardy) late" : nil,
            absent > 0 ? "\(absent) absent" : nil
        ].compactMap(\.self).joined(separator: " · "))
        .font(.caption2.weight(.medium))
        .foregroundStyle(absent > tardy ? Color.red : Color.lateAmber)
        .monospacedDigit()
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
        .accessibilityHidden(true)
    }

    private func dotColor(for status: AttendanceStatus) -> Color {
        switch status {
        case .present: return .green.opacity(0.85)
        case .absent: return .red.opacity(0.85)
        case .tardy: return .lateAmber
        case .leftEarly: return .purple.opacity(0.85)
        case .unmarked: return .secondary.opacity(0.25)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.control, style: .continuous)
            .fill(Color.secondary.opacity(0.06))
    }
}
