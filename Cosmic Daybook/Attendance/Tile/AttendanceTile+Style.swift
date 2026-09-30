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
}
#endif
