#if os(iOS)
import SwiftUI

// MARK: - Menu and accessibility

extension AttendanceTile {

    /// Every status, Absent with its reasons, clearing and the note
    /// (`AttendanceStatusMenu`), when the day can be marked.
    @ViewBuilder
    var menu: some View {
        if canMark {
            AttendanceStatusMenu(
                status: row.status,
                absenceReason: row.absenceReason,
                hasNote: !row.note.isEmpty,
                header: menuHeader,
                statuses: menuStatuses,
                willMark: { marked($0) },
                onSetStatus: onSetStatus,
                onMarkAbsent: onMarkAbsent,
                onNote: onNote
            )
        }
    }

    /// "Birthday · Back after 4 days · Present at 8:02 · by you", leaving out
    /// what isn't so.
    var menuHeader: String? {
        AttendanceStatusMenu.header(for: row, markedBy: markedBy)
    }

    // MARK: - Accessibility

    /// "Maya Stone, birthday, back after 4 days, Present at 8:04".
    var accessibilityName: String {
        let birthday = row.birthday.map { ", \($0.title.lowercased())" } ?? ""
        let away = row.daysAway.map { ", " + AttendanceRules.welcomeBackPhrase(daysAway: $0).lowercased() } ?? ""
        return "\(row.name)\(birthday)\(away), \(markSummary ?? row.status.displayName)"
    }

    /// "Present at 8:04", "Left Early 8:02 → 1:15", "Absent, Sick", or nil
    /// while unmarked.
    var markSummary: String? { AttendanceRules.markSummary(row) }

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
#endif
