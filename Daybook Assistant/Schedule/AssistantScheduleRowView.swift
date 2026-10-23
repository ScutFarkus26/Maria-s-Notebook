import SwiftUI

/// One row of the day: the time and the lane's tag, the title, whose turn it
/// is, the children and the note.
struct AssistantScheduleRowView: View {
    let row: AssistantScheduleRows.Row

    private var laneColor: Color { AssistantScheduleStyle.color(row.laneColorRaw, index: row.laneIndex) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(laneColor)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.time)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(row.laneName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(laneColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(laneColor.opacity(0.14), in: Capsule())
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let marker = row.marker {
                        Text(marker)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                Text(row.title)
                    .font(.body.weight(row.kind == .withGuide ? .regular : .medium))
                    .strikethrough(row.isOut)
                    .foregroundStyle(row.isOut ? .secondary : .primary)
                if let teacher = row.teacher {
                    Text(teacher)
                        .font(.subheadline)
                        .foregroundStyle(row.isOut ? .orange : .secondary)
                }
                if !row.children.isEmpty {
                    Text(row.children.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = row.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// The lanes' colors: the one the guide chose by name, or one by the lane's
/// place.
enum AssistantScheduleStyle {
    private static let palette: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo, .brown]

    private static let named: [String: Color] = [
        "blue": .blue, "purple": .purple, "orange": .orange, "green": .green, "pink": .pink, "teal": .teal,
        "indigo": .indigo, "brown": .brown, "red": .red, "yellow": .yellow, "mint": .mint, "cyan": .cyan,
        "gray": .gray, "grey": .gray
    ]

    static func color(_ raw: String, index: Int) -> Color {
        named[raw.lowercased()] ?? palette[((index % palette.count) + palette.count) % palette.count]
    }
}
