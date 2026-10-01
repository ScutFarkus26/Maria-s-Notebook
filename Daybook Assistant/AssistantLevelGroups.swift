import SwiftUI

/// The grid split into one block per level, chosen in the Classroom sheet
/// (Group by Level): Upper Elementary, then Adolescent, then Lower, the
/// order the front-desk email lists them in. Each block keeps the name
/// order on its own. A class all of one level shows as one grid, with no
/// heading. Only on this iPhone.
enum AssistantLevelGroups {
    static let key = "Assistant.groupsByLevel"

    struct Group<Item> {
        let level: AttendanceEmailLevel
        let items: [Item]
    }

    /// `items` in level blocks, in their order within each block; empty
    /// levels left out, and a level the report doesn't know counted as Lower.
    static func grouped<Item>(
        _ items: [Item],
        level: (Item) -> CDStudent.Level
    ) -> [Group<Item>] {
        let byLevel = Dictionary(grouping: items) {
            AttendanceEmailLevel(rawValue: level($0).rawValue) ?? .lower
        }
        return AttendanceEmailLevel.allCases.compactMap { block in
            guard let items = byLevel[block], !items.isEmpty else { return nil }
            return Group(level: block, items: items)
        }
    }
}

/// A level block's heading: "Upper Elementary" and how many of them are in
/// the room ("9 of 12 here", counted as the bar counts), or just how many on
/// a day ahead.
struct AssistantLevelHeader: View {
    let level: AttendanceEmailLevel
    let rows: [AttendanceRow]
    let isFuture: Bool
    let height: CGFloat
    /// A phone: smaller type, to fit the slimmer heading.
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(level.title)
                .font((isCompact ? Font.footnote : .subheadline).weight(.semibold))
            Spacer(minLength: 8)
            Text(isFuture ? "\(rows.count)" : "\(rows.count(where: \.isInRoom)) of \(rows.count) here")
                .font(isCompact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .frame(height: height)
        .modifier(AssistantGridLabelStyle(isCompact: isCompact))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The count line and the level headings over the grid, alike: their text
/// lined up with the names inside the tiles, plain on Sky and Plain, and on
/// a picture in a frosted capsule, as the tiles frost there.
struct AssistantGridLabelStyle: ViewModifier {
    /// A phone, where the tiles inset their names 12 points rather than 14.
    let isCompact: Bool
    @Environment(\.attendanceBackdropIsQuiet) private var backdropIsQuiet

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, isCompact ? 12 : 14)
            .background {
                if !backdropIsQuiet { Capsule().fill(.regularMaterial) }
            }
    }
}
