// WeekDayColumn.swift
// One day in the merged Lessons & Work calendar.
//
// One stacked list: the day's presentations, banded "Morning" and "Afternoon",
// then its work checks under a "Checks" label. Presentations are ordered —
// dragging one above another sets the sequence they will be given in, and
// dropping one onto a same-lesson card merges the two. Checks are unordered and
// grouped, because "sometime today" is all their position ever meant, so they
// follow the ordered part rather than sit inside it.
//
// For a while they were two lanes side by side, so a long morning could not
// push the checks below the fold. That made every day about 730 points wide,
// and on a 1,500-point window the guide saw a day and a half of the week he
// was planning. One lane at a fifth of the pane shows the whole week, and a
// check is one line now, so a day's checks stay short under its lessons.
//
// The whole day is ONE drop zone, and the bands are labels, not targets.
// Splitting the drop target would invent a way to fail: a presentation dropped
// among the checks would have to be either refused or silently re-aimed.
// Instead the delegate routes by what was dragged, not by where it landed.

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

struct WeekDayColumn: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.calendar) var calendar
    @Environment(\.dependencies) var dependencies

    let day: Date
    let allLessonAssignments: [CDLessonAssignment]
    /// This day's pending presentations, already filtered and ordered by the
    /// parent (`WeekPlanSection.scheduledByDay`) for every column at once.
    let scheduledLessons: [CDLessonAssignment]
    /// The curriculum and the roster, fetched once by `WeekPlanSection` for the
    /// whole strip. Every card on the day reads these arrays; before they were
    /// threaded through, each card ran its own unpredicated fetch of both
    /// tables, so a five-day window with six presentations a day held sixty
    /// live fetched-results controllers.
    let lessons: [CDLesson]
    let students: [CDStudent]
    let visibleKinds: CalendarKindFilter
    /// Already resolved and grouped for this day by the parent, which builds
    /// one lookup for the whole visible range.
    let checkInGroups: [CalendarCheckInGroup]
    let focusedPresentationID: UUID?
    let onClear: (CDLessonAssignment) -> Void
    let onSelect: (CDLessonAssignment) -> Void
    let onOpenCheckInGroup: (CalendarCheckInGroup) -> Void
    let onDropWorkCheckIns: ([UUID], Date) -> Void
    let onDropWork: (UUID, Date) -> Void
    /// What a check-in pill's right-click menu can do — see WeekDayColumn+Bands.
    let pillActions: WorkCheckPillActions
    /// The column's width, an equal share of the strip — see
    /// `WeekPlanSection.columnWidth(forStripWidth:dayCount:)`. Defaulted so a
    /// column can be built on its own, as the menu tests do.
    var columnWidth: CGFloat = WeekPlanSection.minimumColumnWidth

    /// Card frames, written after every layout pass but read only by the drop
    /// delegate and the mid-drag insertion bar. Kept in a reference box rather
    /// than in `@State`: writing state from layout forced a second render of
    /// the whole column after every render.
    @State var itemFrameBox = WeekDayPillFrameBox()
    /// Bumped when the frames move while the insertion bar is showing, so the
    /// bar follows them the way it did when the frames were state.
    @State var itemFrameRevision = 0
    var itemFrames: [UUID: CGRect] { itemFrameBox.frames }
    /// The pill whose "Pick a Day…" calendar is up.
    @State var reschedulingGroupID: UUID?
    @State var zoneSpaceID = UUID()
    @State var isTargeted: Bool = false
    @State var insertionIndex: Int?

    private struct FocusScrollTrigger: Equatable {
        let focusedID: UUID?
        let scheduledIDs: [UUID]
    }

    var scheduledLessonsForDay: [CDLessonAssignment] {
        visibleKinds.showsPresentations ? scheduledLessons : []
    }

    var visibleCheckInGroups: [CalendarCheckInGroup] {
        visibleKinds.showsWork ? checkInGroups : []
    }

    private var focusScrollTrigger: FocusScrollTrigger {
        FocusScrollTrigger(
            focusedID: focusedPresentationID,
            scheduledIDs: scheduledLessonsForDay.compactMap(\.id)
        )
    }

    static let zonePadding: CGFloat = 8

    /// The width the day's cards get: the column less the drop zone's padding.
    /// The insertion bar spans exactly this.
    var contentWidth: CGFloat { max(columnWidth - Self.zonePadding * 2, 0) }

    var isToday: Bool { calendar.isDateInToday(day) }

    private var checkCount: Int {
        visibleCheckInGroups.reduce(0) { $0 + $1.checkIns.count }
    }

    /// "5 · 2 checks": presentations bare, since they are most of what a
    /// column holds, and checks named so the two numbers are not read as one.
    private var headerCountLabel: String {
        var parts: [String] = []
        let presentations = scheduledLessonsForDay.count
        if presentations > 0 {
            parts.append("\(presentations)")
        }
        if checkCount > 0 {
            parts.append(checkCount == 1 ? "1 check" : "\(checkCount) checks")
        }
        return parts.joined(separator: " · ")
    }

    private var headerCountAccessibilityLabel: String {
        var parts: [String] = []
        let presentations = scheduledLessonsForDay.count
        if presentations > 0 {
            parts.append(presentations == 1 ? "1 presentation" : "\(presentations) presentations")
        }
        if checkCount > 0 {
            parts.append(checkCount == 1 ? "1 work check" : "\(checkCount) work checks")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            dayHeader
            dropZone
                .coordinateSpace(name: zoneSpaceID)
                .onPreferenceChange(WeekDayPillFramePreference.self) { frames in
                    // PreferenceKey updates land during layout, so defer the
                    // state write or SwiftUI re-enters layout.
                    Task { @MainActor in
                        itemFrameBox.frames = frames
                        if insertionIndex != nil { itemFrameRevision &+= 1 }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.control))
                .onDrop(of: [UTType.text], delegate: dropDelegate)
                .frame(maxHeight: .infinity)
        }
        .frame(width: columnWidth)
    }

    private var dayHeader: some View {
        HStack(spacing: 6) {
            Text(day.formatted(Date.FormatStyle().weekday(.abbreviated)))
                .font(.caption.weight(.semibold))
            Text(day.formatted(Date.FormatStyle().day()))
                .font(.headline.weight(.semibold))
            Spacer()
            // Only ever on a day that has a clash — see WeekDayColumn+Balance.
            balanceButton
            if !headerCountLabel.isEmpty {
                Text(headerCountLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .accessibilityLabel(headerCountAccessibilityLabel)
            }
        }
        .padding(.horizontal, 6)
    }

    private var dropDelegate: WeekDayColumnDropDelegate {
        WeekDayColumnDropDelegate(
            calendar: calendar,
            viewContext: viewContext,
            allLessonAssignments: allLessonAssignments,
            day: day,
            orderedPresentationIDs: { scheduledLessonsForDay.compactMap(\.id) },
            itemFramesProvider: { itemFrames },
            onDropWorkCheckIns: onDropWorkCheckIns,
            onDropWork: onDropWork,
            onTargetChange: { targeted in
                adaptiveWithAnimation(.easeInOut(duration: 0.12)) { isTargeted = targeted }
            },
            onInsertionIndexChange: { idx in
                if insertionIndex != idx {
                    adaptiveWithAnimation(
                        .interactiveSpring(response: 0.16, dampingFraction: 0.85)
                    ) { insertionIndex = idx }
                }
            }
        )
    }

    private var dropZone: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.control, style: .continuous)
                .fill(Color.primary.opacity(isTargeted ? 0.08 : 0.04))
            if isTargeted {
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.control, style: .continuous)
                    .stroke(Color.accentColor.opacity(UIConstants.OpacityConstants.prominent), lineWidth: 2)
            } else if isToday {
                // Today, found at a glance across the week; faint enough that
                // the drop highlight above still reads as the louder thing.
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.control, style: .continuous)
                    .stroke(Color.accentColor.opacity(UIConstants.OpacityConstants.moderate), lineWidth: 1)
            }

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    dayList
                        .padding(Self.zonePadding)
                }
                .task(id: focusScrollTrigger) {
                    guard let focusedPresentationID,
                          focusScrollTrigger.scheduledIDs.contains(focusedPresentationID) else {
                        return
                    }
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollProxy.scrollTo(focusedPresentationID, anchor: .center)
                    }
                }
            }

            insertionIndicator
        }
    }
}

/// Holds a day column's card frames without making them observable state.
final class WeekDayPillFrameBox {
    var frames: [UUID: CGRect] = [:]
}

/// Reports each presentation card's frame so the drop delegate can compute an
/// insertion point. Top-level because the day column's content lives in an
/// extension in another file.
struct WeekDayPillFramePreference: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
