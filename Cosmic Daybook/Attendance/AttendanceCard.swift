// AttendanceCard.swift
// One child's card on the Mac and iPad roll. (The iPhone draws `AttendanceTile`.)

import SwiftUI
import CoreData

struct AttendanceCard: View {
    let row: AttendanceRow
    let isEditing: Bool
    /// Who made the mark, when it wasn't you ("Rivka").
    let markedBy: String?
    /// The statuses the menu offers on this day.
    let menuStatuses: [AttendanceStatus]
    /// A click or tap: the next status in the cycle.
    let onTap: () -> Void
    let onSetStatus: (AttendanceStatus) -> Void
    let onMarkAbsent: (AbsenceReason) -> Void
    let onNote: () -> Void
    /// Leaving Early…, when the day and the mark allow a pickup time.
    var onPickup: (() -> Void)?
    /// Back in Class, for a child marked Left Early.
    var onBack: (() -> Void)?

    private var status: AttendanceStatus { row.status }
    private var absenceReason: AbsenceReason { row.absenceReason }
    private var hasNote: Bool { !row.note.isEmpty }

    /// Who marked this, shown only when it wasn't you. Your own marks carry no
    /// name — labelling every one of them would bury the handful that came
    /// from someone else, which is the only case worth reading.
    @ViewBuilder
    private var markedByLabel: some View {
        if let markedBy {
            HStack(spacing: 3) {
                Image(systemName: "person.crop.circle")
                Text(markedBy)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(AppTheme.ScaledFont.captionSmall)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Marked by \(markedBy)")
        }
    }

    private var accentColor: Color {
        switch status {
        case .present: return .green
        case .tardy: return .blue
        case .absent: return .red
        case .leftEarly: return .purple
        case .unmarked: return .gray.opacity(UIConstants.OpacityConstants.muted)
        }
    }

    /// When the child came in ("8:02"), or came and went ("8:02 → 1:15").
    /// Only marks made on their own day carry a time.
    private var timeText: String? {
        switch status {
        case .present, .tardy: return row.markedAt.map(AttendanceClock.string)
        case .leftEarly: return AttendanceRules.leftEarlyTimes(row)
        case .absent, .unmarked: return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 8) {
            Text(row.student.shortName)
                .font(AppTheme.ScaledFont.titleSmall)
                .lineLimit(1)
                .truncationMode(.tail)

            if let birthday = row.birthday {
                Image(systemName: birthday.symbol)
                    .font(.caption)
                    .foregroundStyle(.pink)
                    .help(birthday.title)
                    .accessibilityLabel(birthday.title)
            }

            // Back after days away: welcome them at the door.
            if let daysAway = row.daysAway {
                let phrase = AttendanceRules.welcomeBackPhrase(daysAway: daysAway)
                Image(systemName: "hand.wave.fill")
                    .font(.caption)
                    .foregroundStyle(.teal)
                    .help(phrase)
                    .accessibilityLabel(phrase)
            }

            // Visual indicator that a note exists
            if hasNote {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            // Small note icon at far right (only when no note exists and editing)
            if !hasNote && isEditing {
                Button(action: onNote) {
                    Image(systemName: "square.and.pencil")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Add Note")
                }
                .buttonStyle(.plain)
            }
        }

        HStack(spacing: 6) {
            // Compact status pill with absence reason indicator
            StatusPill(
                text: status.displayName,
                color: accentColor,
                icon: (status == .absent && absenceReason != .none) ? absenceReason.icon : nil
            )
            .id(status)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
            .adaptiveAnimation(.bouncy(duration: 0.3, extraBounce: 0.2), value: status)

            if let timeText {
                Text(timeText)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            // Left early and came back: "out 11:15–12:40".
            if let trip = AttendanceRules.tripText(row) {
                Label(trip, systemImage: "arrow.uturn.backward")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            // Due to be picked up early: "leaves 1:30" until they go.
            if let pickup = AttendanceRules.pickupText(row) {
                Label(pickup, systemImage: "figure.walk.departure")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.purple)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }

        markedByLabel

        // Clicking the note opens the editor only if editing, otherwise static display
        if hasNote {
            if isEditing {
                Button(action: onNote) { noteLine }
                    .buttonStyle(.plain)
                    .help("Edit note")
            } else {
                noteLine
            }
        }
    }

    private var noteLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "note.text")
                .foregroundStyle(.secondary)
            Text(row.note)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var background: some View {
        // Neutral card background with subtle elevation
        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.tile, style: .continuous)
            .fill(Color.windowBackgroundColor())
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.tile, style: .continuous)
                    .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle), lineWidth: 1)
            )
    }

    private var cardBody: some View {
        HStack(spacing: 0) {
            // Left accent bar indicating status color
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)
                .clipRounded(2)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(10)
        }
        .frame(minHeight: 80)
        .background(background)
        .clipRounded(UIConstants.CornerRadius.tile, style: .continuous)
        .contentShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.tile, style: .continuous))
        .adaptiveAnimation(.spring(response: 0.4, dampingFraction: 0.7), value: status)
    }

    var body: some View {
        cardBody
#if os(macOS)
            .highPriorityGesture(TapGesture(count: 1).onEnded { if isEditing { onTap() } })
#else
            .onTapGesture { if isEditing { onTap() } }
#endif
            .contextMenu {
                if isEditing {
                    AttendanceStatusMenu(
                        status: status,
                        absenceReason: absenceReason,
                        hasNote: hasNote,
                        header: AttendanceStatusMenu.header(for: row, markedBy: markedBy),
                        statuses: menuStatuses,
                        onSetStatus: onSetStatus,
                        onMarkAbsent: onMarkAbsent,
                        onNote: onNote,
                        onPickup: onPickup,
                        leavesAt: row.leavesAt,
                        onBack: onBack
                    )
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(hasNote ? row.note : "No note")
            .accessibilityHint(isEditing ? "Changes the attendance status" : "")
    }

    /// "Maya Stone, birthday, back after 4 days, Present at 8:04".
    private var accessibilityLabel: String {
        let birthday = row.birthday.map { ", \($0.title.lowercased())" } ?? ""
        let away = row.daysAway.map { ", " + AttendanceRules.welcomeBackPhrase(daysAway: $0).lowercased() } ?? ""
        let trip = AttendanceRules.tripText(row).map { ", \($0)" } ?? ""
        let pickup = AttendanceRules.pickupText(row).map { ", \($0)" } ?? ""
        let mark = AttendanceRules.markSummary(row) ?? status.displayName
        return "\(row.name)\(birthday)\(away), \(mark)\(trip)\(pickup)"
    }
}
