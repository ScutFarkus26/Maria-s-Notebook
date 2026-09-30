import SwiftUI

// MARK: - Menu and accessibility

extension AssistantAttendanceTile {

    /// The header carries what the phone tile has no room for ("Present at
    /// 8:02 · by you", "Absent, Sick · by your guide"). Then Present, Tardy and
    /// Left Early; Absent with its reasons in one step; clearing; the note.
    /// The current choice wears a checkmark in place of its glyph. Ahead of
    /// the day only Absent and clearing are offered.
    @ViewBuilder
    var menu: some View {
        if canMark {
            Section {
                ForEach(menuStatuses.filter { $0 != .absent && $0 != .unmarked }, id: \.self) { status in
                    Button {
                        marked(status)
                        onSetStatus(status)
                    } label: {
                        Label(status.displayName, systemImage: status == row.status ? "checkmark" : Self.glyph(status))
                    }
                }
                if menuStatuses.contains(.absent) {
                    absentMenu
                }
            } header: {
                if let menuHeader { Text(menuHeader) }
            }
            if row.status != .unmarked, menuStatuses.contains(.unmarked) {
                Button("Clear Mark", systemImage: "circle.dashed") {
                    marked(.unmarked)
                    onSetStatus(.unmarked)
                }
            }
            Button(row.note.isEmpty ? "Add Note" : "Edit Note", systemImage: "text.alignleft", action: onNote)
        }
    }

    /// "Birthday · Back after 4 days · Present at 8:02 · by you", leaving out
    /// what isn't so.
    var menuHeader: String? {
        let mark = markSummary.map { summary in markedBy.map { "\(summary) · by \($0)" } ?? summary }
        let away = row.daysAway.map(AssistantWelcomeBack.phrase(daysAway:))
        let parts = [row.birthday?.title, away, mark].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Absent, then why. "Other…" goes on to the note, which says what.
    var absentMenu: some View {
        Menu {
            absentChoice(.none, title: "No Reason", systemImage: "xmark")
            ForEach(AbsenceReason.given, id: \.self) { reason in
                absentChoice(
                    reason,
                    title: reason == .other ? "Other…" : reason.displayName,
                    systemImage: reason.icon
                )
            }
        } label: {
            Label("Absent", systemImage: row.status == .absent ? "checkmark" : "xmark")
        }
    }

    func absentChoice(_ reason: AbsenceReason, title: String, systemImage: String) -> some View {
        let isCurrent = row.status == .absent && row.absenceReason == reason
        return Button {
            marked(.absent)
            onMarkAbsent(reason)
        } label: {
            Label(title, systemImage: isCurrent ? "checkmark" : systemImage)
        }
    }

    // MARK: - Accessibility

    /// "Maya Stone, birthday, back after 4 days, Present at 8:04".
    var accessibilityName: String {
        let birthday = row.birthday.map { ", \($0.title.lowercased())" } ?? ""
        let away = row.daysAway.map { ", " + AssistantWelcomeBack.phrase(daysAway: $0).lowercased() } ?? ""
        return "\(row.name)\(birthday)\(away), \(markSummary ?? row.status.displayName)"
    }

    /// "Present at 8:04", "Left Early 8:02 → 1:15", "Absent, Sick", or nil
    /// while unmarked. Marks made on another day carry no time.
    var markSummary: String? {
        guard row.status != .unmarked else { return nil }
        var text = row.status.displayName
        switch row.status {
        case .absent where row.absenceReason != .none:
            text += ", \(row.absenceReason.displayName)"
        case .leftEarly:
            if let arrived = row.markedAt, let left = row.leftAt {
                text += " \(AssistantClock.string(arrived)) → \(AssistantClock.string(left))"
            } else if let left = row.leftAt {
                text += " at \(AssistantClock.string(left))"
            }
        case .present, .tardy:
            if let markedAt = row.markedAt { text += " at \(AssistantClock.string(markedAt))" }
        default:
            break
        }
        return text
    }

    var voiceOverHint: String {
        switch tapTarget {
        case .present: return "Double tap to mark present"
        case .tardy: return "Double tap to mark tardy"
        case .absent: return "Double tap to mark absent again"
        case .unmarked: return "Double tap to clear the mark"
        default: return "\(tapHint). Touch and hold to change the mark"
        }
    }
}
