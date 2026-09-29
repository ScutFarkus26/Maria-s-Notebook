import Foundation

/// Mark times as the Assistant shows them: in the tile's menu and detail line,
/// and in the bar's "Everyone's here · 8:14".
@MainActor
enum AssistantClock {
    /// "8:02", not "8:02 AM": it's always the school day, and the header and
    /// the detail line need the width for an arrival and a departure.
    static func string(_ date: Date) -> String {
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
