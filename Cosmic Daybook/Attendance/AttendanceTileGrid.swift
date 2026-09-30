#if os(iOS)
import SwiftUI

/// The iPhone's roll: the Daybook Assistant's tiles, three across, each in
/// a fixed place so a name never moves under a finger. A tap marks present
/// (late, once arrival has closed on this phone); a long press offers every
/// status, Absent with its reason, and the note. The tiles grow to fill a
/// tall phone. A sideways swipe steps a school day.
///
/// When a mark here completes the roll, a ripple runs across the grid.
struct AttendanceTileGrid: View {
    let viewModel: AttendanceViewModel
    let isEditing: Bool
    let actions: AttendanceGridActions
    let markedBy: (AttendanceRow) -> String?
    let onNote: (AttendanceRow) -> Void
    var onStepDay: ((Bool) -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The grid's room inside the scroll view, for sizing the tiles.
    @State private var space: CGSize = .zero
    /// Which way the last swipe went, so the next day slides in from there.
    @State private var stepEdge: Edge = .trailing

    private static let columnWidth: CGFloat = 105
    private static let spacing: CGFloat = 8
    private static let verticalPadding: CGFloat = 8

    /// Three (or more) adaptive columns; two at accessibility text sizes.
    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: 2)
        }
        return [GridItem(.adaptive(minimum: Self.columnWidth), spacing: Self.spacing)]
    }

    private var columnCount: Int {
        if dynamicTypeSize.isAccessibilitySize { return 2 }
        return max(1, Int((space.width + Self.spacing) / (Self.columnWidth + Self.spacing)))
    }

    private var tileHeight: CGFloat {
        guard !dynamicTypeSize.isAccessibilitySize else { return AttendanceTile.phoneHeight }
        return AttendanceTile.fittedPhoneHeight(
            visibleHeight: space.height - Self.verticalPadding * 2,
            columns: columnCount,
            count: viewModel.rows.count,
            spacing: Self.spacing
        )
    }

    var body: some View {
        let height = tileHeight
        ScrollView {
            LazyVGrid(columns: columns, spacing: Self.spacing) {
                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                    tile(row, height: height, index: index)
                }
            }
            .padding(.vertical, Self.verticalPadding)
            .id(viewModel.selectedDate)
            .transition(.push(from: stepEdge))
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { space = $0 }
        .simultaneousGesture(daySwipe)
    }

    private func tile(_ row: AttendanceRow, height: CGFloat, index: Int) -> some View {
        AttendanceTile(
            row: row,
            tapTarget: viewModel.statusAfterTap(for: row),
            tapHint: viewModel.isFuture ? "Only absences ahead" : "Hold to change",
            menuStatuses: viewModel.menuStatuses,
            canMark: isEditing,
            usesShortName: true,
            height: height,
            onTap: { actions.tap(row) },
            markedBy: markedBy(row),
            onSetStatus: { actions.setStatus($0, row) },
            onMarkAbsent: { reason in
                actions.markAbsent(reason, row)
                // "Other" is only as good as the note that says what.
                if reason == .other { onNote(row) }
            },
            onNote: { onNote(row) },
            rippleTrigger: viewModel.completions,
            rippleDelay: rippleDelay(at: index)
        )
    }

    /// The ripple runs row by row, and left to right within a row.
    private func rippleDelay(at index: Int) -> Double {
        Double(index / columnCount) * 0.07 + Double(index % columnCount) * 0.035
    }

    /// A clearly sideways swipe steps a day; anything more vertical is left
    /// to scrolling, and a long press to the tile's menu.
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard let onStepDay, let forward = AttendanceDaySwipe.step(for: value.translation) else { return }
                stepEdge = forward ? .trailing : .leading
                withAnimation(.smooth(duration: 0.3)) {
                    onStepDay(forward)
                }
            }
    }
}
#endif
