import SwiftUI

/// The day's count at the top of the grid: "17 of 22 here" (in the room now,
/// as the bar's fill counts them, out of the whole class), with "1 late ·
/// 2 absent · 3 not marked" beside it while it fits. On a day ahead, where
/// only absences can be marked, "22 children".
struct AssistantClassCount: View {
    let rows: [AttendanceRow]
    let isFuture: Bool

    private var mainLine: String {
        let total = rows.count
        if isFuture { return total == 1 ? "1 child" : "\(total) children" }
        return "\(rows.count(where: \.isInRoom)) of \(total) here"
    }

    private var detailLine: String? { AttendanceRules.detailLine(rows) }

    var body: some View {
        // The detail goes first when the line is too long for it.
        ViewThatFits(in: .horizontal) {
            line(showsDetail: true)
            line(showsDetail: false)
        }
        .monospacedDigit()
        .lineLimit(1)
        .contentTransition(.numericText())
        .animation(.smooth, value: mainLine)
        .animation(.smooth, value: detailLine)
        .accessibilityElement(children: .combine)
    }

    private func line(showsDetail: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(mainLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if showsDetail, let detailLine {
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
