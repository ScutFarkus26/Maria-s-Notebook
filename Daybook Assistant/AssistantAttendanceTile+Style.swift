import SwiftUI

// MARK: - Style and times

extension AssistantAttendanceTile {

    // MARK: - Style

    /// Present, late and left early all mean the child came in.
    var isHere: Bool {
        switch row.status {
        case .present, .tardy, .leftEarly: return true
        case .absent, .unmarked: return false
        }
    }

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

    /// A status's glyph in the long-press menu.
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

    var fill: Color {
        if isHere { return .green }
        if row.status == .absent { return .clear }
        return Color(.secondarySystemGroupedBackground)
    }

    @ViewBuilder
    var border: some View {
        if row.status == .absent {
            shape.strokeBorder(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        } else if !isHere {
            shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    // MARK: - Times

    /// "8:02", not "8:02 AM": it's always the school day, and the header and
    /// the detail line need the width for an arrival and a departure.
    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// The locale's own hour-and-minute pattern ("h:mm a", "HH:mm") without
    /// its AM/PM marker. (`hour(.defaultDigits(amPM: .omitted))` pads the
    /// hour to "08:02" on iOS 26.)
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "h:mm"
        formatter.dateFormat = pattern.replacingOccurrences(of: "a", with: "").trimmingCharacters(in: .whitespaces)
        return formatter
    }()
}

/// One VoiceOver element per tile: its label, the note as its value, a tap
/// that marks, and a Note action.
struct TileAccessibility: ViewModifier {
    let label: String
    let note: String
    let hint: String
    let onTap: () -> Void
    let onNote: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(note)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .accessibilityAction(named: "Note", onNote)
    }
}
