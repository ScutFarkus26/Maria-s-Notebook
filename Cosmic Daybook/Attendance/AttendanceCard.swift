// AttendanceCard.swift
// One child's tile on the Mac and iPad roll. (The iPhone draws `AttendanceTile`.)

import SwiftUI
import CoreData

/// One child on the Mac and iPad roll, in the Daybook Assistant's tile
/// language: a child in the room is filled green, a child not in yet is the
/// one empty tile, an absence is dashed and dimmed, a child who left early
/// is lavender, and Late wears an amber ring. Present carries no word at
/// all, so the handful of exceptions are what the eye finds.
///
/// A click does what the Assistant's tap does (`AttendanceRules.statusAfterTap`):
/// present during arrival, late after Close Arrival. Everything else is on
/// the right-click menu.
struct AttendanceCard: View {
    let row: AttendanceRow
    let isEditing: Bool
    /// Whether the day has arrived: a child unmarked ahead of the day isn't
    /// "not in yet".
    let isFuture: Bool
    /// The keyboard's selection.
    let isSelected: Bool
    /// Who made the mark, when it wasn't you ("Rivka").
    let markedBy: String?
    /// The statuses the menu offers on this day.
    let menuStatuses: [AttendanceStatus]
    /// A click or tap: present during arrival, late after it closes.
    let onTap: () -> Void
    let onSetStatus: (AttendanceStatus) -> Void
    let onMarkAbsent: (AbsenceReason) -> Void
    let onNote: () -> Void
    let onHistory: () -> Void
    /// Leaving Early…, when the day and the mark allow a pickup time.
    var onPickup: (() -> Void)?
    /// Back in Class, for a child marked Left Early.
    var onBack: (() -> Void)?

    static let height: CGFloat = 64
    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    private var status: AttendanceStatus { row.status }
    private var hasNote: Bool { !row.note.isEmpty }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
            .background { Self.shape.fill(fill) }
            .overlay { border }
            .overlay {
                if isSelected {
                    Self.shape.inset(by: -3).strokeBorder(Color.accentColor, lineWidth: 2.5)
                }
            }
            .contentShape(Self.shape)
            .animation(.smooth(duration: 0.25), value: status)
            .onTapGesture { if isEditing { onTap() } }
            .contextMenu { menu }
            .help(helpText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(hasNote ? row.note : "")
            .accessibilityHint(isEditing ? "Marks present, or late once arrival has closed" : "")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(row.student.shortName)
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(nameStyle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(2)
                glyphs
                Spacer(minLength: 4)
                if let timeText {
                    Text(timeText)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(timeStyle)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .fontWeight(captionIsStatus ? .semibold : .regular)
                    .foregroundStyle(captionStyle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private var glyphs: some View {
        if status == .tardy {
            Image(systemName: "clock")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.lateAmber)
                .accessibilityHidden(true)
        }
        if let birthday = row.birthday {
            Image(systemName: birthday.symbol)
                .font(.caption)
                .foregroundStyle(.pink)
                .accessibilityHidden(true)
        }
        // Back after days away: welcome them at the door.
        if row.daysAway != nil {
            Image(systemName: "hand.wave.fill")
                .font(.caption)
                .foregroundStyle(.teal)
                .accessibilityHidden(true)
        }
        // A note the caption doesn't already show.
        if hasNote, caption != row.note {
            Image(systemName: "text.alignleft")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Words

    /// When the child came in ("8:02"). Only marks made on their own day
    /// carry a time; a child who left early shows when they went instead,
    /// in the caption, where it has the room.
    private var timeText: String? {
        switch status {
        case .present, .tardy: return row.markedAt.map(AttendanceClock.string)
        case .leftEarly, .absent, .unmarked: return nil
        }
    }

    /// The tile's second line: the exception first ("Late", "Absent · Sick",
    /// "not in yet"), then what's coming or came ("leaves 1:30", "out
    /// 11:15–12:40"), then who marked it when it wasn't you.
    private var caption: String? {
        var parts: [String] = []
        if let statusWord { parts.append(statusWord) }
        if let pickup = AttendanceRules.pickupText(row) { parts.append(pickup) }
        if let trip = AttendanceRules.tripText(row) { parts.append(trip) }
        if let markedBy, status != .unmarked { parts.append("by \(markedBy)") }
        if parts.isEmpty, hasNote { parts.append(row.note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var statusWord: String? {
        switch status {
        case .present: return row.birthday?.title
        case .tardy: return "Late"
        case .leftEarly: return row.leftAt.map { "Left \(AttendanceClock.string($0))" } ?? "Left early"
        case .absent:
            return row.absenceReason == .none ? "Absent" : "Absent · \(row.absenceReason.displayName)"
        case .unmarked: return isFuture ? nil : "not in yet"
        }
    }

    /// The status word, not a pickup or a name, leads the line.
    private var captionIsStatus: Bool {
        switch status {
        case .tardy, .leftEarly, .absent: return true
        case .present, .unmarked: return false
        }
    }

    // MARK: - Style

    private var fill: Color {
        switch status {
        case .present, .tardy: return Color.green.opacity(0.22)
        case .leftEarly: return Color.purple.opacity(0.14)
        case .absent: return Color.secondary.opacity(0.06)
        case .unmarked: return Color.windowBackgroundColor()
        }
    }

    @ViewBuilder
    private var border: some View {
        switch status {
        case .tardy:
            Self.shape.strokeBorder(Color.lateAmber.opacity(0.75), lineWidth: 2)
        case .absent:
            Self.shape.strokeBorder(
                Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
        case .unmarked:
            Self.shape.strokeBorder(Color.primary.opacity(isFuture ? 0.12 : 0.3), lineWidth: 1.5)
        case .present, .leftEarly:
            if row.birthday != nil {
                Self.shape.strokeBorder(Color.pink.opacity(0.8), lineWidth: 2)
            }
        }
    }

    private var nameStyle: Color {
        status == .absent ? .secondary : .primary
    }

    private var timeStyle: Color {
        switch status {
        case .tardy: return .lateAmber
        case .leftEarly: return .purple
        default: return .secondary
        }
    }

    private var captionStyle: Color {
        switch status {
        case .tardy: return .lateAmber
        case .leftEarly: return .purple
        case .absent: return .red
        case .present, .unmarked: return .secondary
        }
    }

    // MARK: - Menu

    @ViewBuilder
    private var menu: some View {
        if isEditing {
            AttendanceStatusMenu(
                status: status,
                absenceReason: row.absenceReason,
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
            Divider()
        }
        Button("Attendance History…", systemImage: "calendar", action: onHistory)
    }

    // MARK: - Help and accessibility

    private var helpText: String {
        guard isEditing else { return "This day is locked" }
        return hasNote ? row.note : "Click to mark · right-click for more"
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
