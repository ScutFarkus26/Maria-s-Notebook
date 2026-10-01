import SwiftUI

/// The day's count at a glance: "17 here" large, who's in the room now, and
/// under it, small, "1 late · 1 left early · 2 absent". A child marked Left
/// Early leaves the large number. Shared by the Daybook Assistant's bar and
/// the notebook's roll on the Mac and iPad.
struct AttendanceHereCount: View {
    let rows: [AttendanceRow]
    var alignment: HorizontalAlignment = .leading

    private var hereLine: String { AttendanceRules.hereLine(rows) }
    private var detailLine: String? { AttendanceRules.detailLine(rows) }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(hereLine)
                .font(Self.hereFont)
                .foregroundStyle(.primary)
            if let detailLine {
                Text(detailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .contentTransition(.numericText())
        .animation(.smooth, value: hereLine)
        .animation(.smooth, value: detailLine)
        .accessibilityElement(children: .combine)
    }

    /// A Mac's title3 is barely bigger than its body text.
    private static var hereFont: Font {
        #if os(macOS)
        .title2.weight(.semibold)
        #else
        .title3.weight(.semibold)
        #endif
    }
}
