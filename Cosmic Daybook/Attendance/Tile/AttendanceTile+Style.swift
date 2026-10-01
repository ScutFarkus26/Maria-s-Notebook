#if os(iOS)
import SwiftUI

// MARK: - Style and times

extension AttendanceTile {

    // MARK: - Style

    /// Present, late and left early all mean the child came in.
    var isHere: Bool { row.isHere }

    static func cornerGlyph(for status: AttendanceStatus) -> String? {
        switch status {
        case .tardy: return "clock"
        case .leftEarly: return "arrow.right"
        case .present, .absent, .unmarked: return nil
        }
    }

    /// A mark's glyph at the start of a roomy tile's detail line.
    static func tileGlyph(for status: AttendanceStatus) -> String? {
        switch status {
        case .present: return "checkmark"
        case .absent: return "xmark"
        case .tardy: return "clock"
        case .leftEarly: return "arrow.right"
        case .unmarked: return nil
        }
    }

    /// Black on the solid green in both appearances: system green is light
    /// enough in each that black reads better than white.
    var nameStyle: Color {
        switch row.status {
        case .present, .tardy, .leftEarly: return .black
        // Dimmed, but readable: during Late these are the tiles she taps
        // when a child comes in.
        case .absent: return Color(.secondaryLabel)
        case .unmarked: return .primary
        }
    }

    @ViewBuilder
    var border: some View {
        if row.birthday != nil {
            shape.strokeBorder(
                Self.partyColors,
                style: StrokeStyle(lineWidth: 2, dash: row.status == .absent ? [5, 4] : [])
            )
        } else if row.status == .absent {
            // A shade darker over a picture, where the frost softens it.
            shape.strokeBorder(
                Color(quietBackdrop ? .tertiaryLabel : .secondaryLabel),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
        } else if !isHere {
            shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    /// One-line tiles have no detail line, so a note and a pickup still to
    /// come show in the other corner (the time itself is in the menu header).
    @ViewBuilder
    var phoneNoteGlyph: some View {
        if isOneLine && (!row.note.isEmpty || pickupText != nil) {
            HStack(spacing: 3) {
                if pickupText != nil {
                    Image(systemName: "figure.walk.departure")
                }
                if !row.note.isEmpty {
                    Image(systemName: "text.alignleft")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(nameStyle.opacity(0.7))
            .padding(6)
            .accessibilityHidden(true)
        }
    }
}
#endif
