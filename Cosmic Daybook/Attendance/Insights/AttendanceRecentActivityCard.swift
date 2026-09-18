// AttendanceRecentActivityCard.swift
// Sidebar card showing the last few school days' notable attendance events.

import SwiftUI

struct AttendanceRecentActivityCard: View {
    let entries: [AttendanceRecentActivityEntry]
    let onSelectDate: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Recent Activity")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))

            if entries.isEmpty {
                Text("Nothing notable in recent days.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AppTheme.Spacing.small)
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            onSelectDate(entry.date)
                        } label: {
                            daySection(for: entry)
                        }
                        .buttonStyle(.plain)

                        if index < entries.count - 1 {
                            Divider()
                                .opacity(0.4)
                        }
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(cardBackground)
    }

    private func daySection(for entry: AttendanceRecentActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(weekdayLabel(for: entry.date))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(monthDayLabel(for: entry.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.events) { event in
                    eventRow(event)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func eventRow(_ event: AttendanceActivityEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
            Circle()
                .fill(statusColor(event.status))
                .frame(width: 7, height: 7)
                .alignmentGuide(.firstTextBaseline) { dim in dim[.bottom] - 2 }

            Text(event.studentName)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)

            Text("·")
                .font(.callout)
                .foregroundStyle(.tertiary)

            Text(statusPhrase(event.status))
                .font(.callout)
                .foregroundStyle(statusColor(event.status))

            if let reasonLabel = reasonLabel(event.reason) {
                Text(reasonLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func statusColor(_ status: AttendanceStatus) -> Color {
        switch status {
        case .present: return .green
        case .absent: return .red
        case .tardy: return .blue
        case .leftEarly: return .purple
        case .unmarked: return .secondary
        }
    }

    private func statusPhrase(_ status: AttendanceStatus) -> String {
        switch status {
        case .absent: return "absent"
        case .tardy: return "tardy"
        case .leftEarly: return "left early"
        case .present: return "present"
        case .unmarked: return ""
        }
    }

    private func reasonLabel(_ reason: AbsenceReason) -> String? {
        switch reason {
        case .sick: return "sick"
        case .vacation: return "vacation"
        case .none: return nil
        }
    }

    // Both of these run once per row. `DateFormatter` construction is expensive,
    // and `DateFormatters` already holds exactly these two shapes.
    private func weekdayLabel(for date: Date) -> String {
        DateFormatters.weekdayFull.string(from: date)
    }

    private func monthDayLabel(for date: Date) -> String {
        DateFormatters.shortMonthDay.string(from: date)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.secondary.opacity(0.06))
    }
}
