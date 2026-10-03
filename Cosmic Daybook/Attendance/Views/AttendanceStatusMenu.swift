import SwiftUI

/// The long-press (or right-click) menu on a child's attendance: any status
/// directly, Absent with its reason in one step, clearing, the note,
/// Leaving Early… for a pickup time ahead of it, and Back in Class for a
/// child who left early and has come back.
/// Shared by the notebook's cards and both apps' phone tiles.
///
/// The header carries what a tile has no room for ("Present at 8:02 · by
/// Rivka"). The current choice wears a checkmark in place of its glyph.
/// Ahead of the day only Absent and clearing are offered (`statuses`).
struct AttendanceStatusMenu: View {
    let status: AttendanceStatus
    let absenceReason: AbsenceReason
    let hasNote: Bool
    let header: String?
    /// The statuses this day allows (`AttendanceRules.menuStatuses`).
    let statuses: [AttendanceStatus]
    /// Runs just before a mark, for the tile's motion.
    var willMark: (AttendanceStatus) -> Void = { _ in }
    let onSetStatus: (AttendanceStatus) -> Void
    /// Absent with a reason (`.none` for no reason), in one step.
    let onMarkAbsent: (AbsenceReason) -> Void
    let onNote: () -> Void
    /// Opens the pickup-time sheet; nil when the day or the mark doesn't
    /// allow one (`AttendanceRules.allowsPickup`).
    var onPickup: (() -> Void)?
    /// The pickup time already set, if any: the item reads Change Pickup Time….
    var leavesAt: Date?
    /// Back in Class, first in the menu; nil unless the child is marked Left
    /// Early (`AttendanceRules.allowsBack`).
    var onBack: (() -> Void)?

    var body: some View {
        Section {
            if let onBack {
                Button("Back in Class", systemImage: "arrow.uturn.backward") {
                    // Back is to present or late: the tile's "here" motion.
                    willMark(.present)
                    onBack()
                }
            }
            ForEach(statuses.filter { $0 != .absent && $0 != .unmarked }, id: \.self) { choice in
                Button {
                    willMark(choice)
                    onSetStatus(choice)
                } label: {
                    Label(choice.displayName, systemImage: choice == status ? "checkmark" : Self.glyph(choice))
                }
            }
            if statuses.contains(.absent) {
                absentMenu
            }
        } header: {
            if let header { Text(header) }
        }
        if status != .unmarked, statuses.contains(.unmarked) {
            Button("Clear Mark", systemImage: "circle.dashed") {
                willMark(.unmarked)
                onSetStatus(.unmarked)
            }
        }
        if let onPickup {
            Button(
                leavesAt == nil ? "Leaving Early…" : "Change Pickup Time…",
                systemImage: "figure.walk.departure",
                action: onPickup
            )
        }
        Button(hasNote ? "Edit Note" : "Add Note", systemImage: "text.alignleft", action: onNote)
    }

    /// Absent, then why. "Other…" goes on to the note, which says what.
    private var absentMenu: some View {
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
            Label("Absent", systemImage: status == .absent ? "checkmark" : "xmark")
        }
    }

    private func absentChoice(_ reason: AbsenceReason, title: String, systemImage: String) -> some View {
        let isCurrent = status == .absent && absenceReason == reason
        return Button {
            willMark(.absent)
            onMarkAbsent(reason)
        } label: {
            Label(title, systemImage: isCurrent ? "checkmark" : systemImage)
        }
    }

    /// A status's glyph in the menu.
    static func glyph(_ status: AttendanceStatus) -> String {
        switch status {
        case .unmarked: return "circle.dashed"
        // Not a checkmark: that marks the current choice in the menu.
        case .present: return "figure.walk.arrival"
        case .absent: return "xmark"
        case .tardy: return "clock"
        case .leftEarly: return "arrow.right"
        }
    }

    /// "Birthday · Back after 4 days · Present at 8:02 · by you · out
    /// 11:15–12:40 · leaves 1:30", leaving out what isn't so.
    static func header(for row: AttendanceRow, markedBy: String?) -> String? {
        let mark = AttendanceRules.markSummary(row).map { summary in
            markedBy.map { "\(summary) · by \($0)" } ?? summary
        }
        let away = row.daysAway.map(AttendanceRules.welcomeBackPhrase(daysAway:))
        let parts = [
            row.birthday?.title, away, mark, AttendanceRules.tripText(row), AttendanceRules.pickupText(row)
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
