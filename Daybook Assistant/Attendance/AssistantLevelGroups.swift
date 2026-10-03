import SwiftUI

/// Group by Level, chosen in the Classroom sheet: the grid split into one
/// block per level (`AttendanceLevelGroups`). A class all of one level shows
/// as one grid, with no heading. Only on this iPhone.
enum AssistantLevelGroups {
    static let key = "Assistant.groupsByLevel"
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
