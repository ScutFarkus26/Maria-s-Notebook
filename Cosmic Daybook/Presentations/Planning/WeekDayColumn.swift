// WeekDayColumn.swift
// One day in the merged Lessons & Work calendar.
//
// Two lanes side by side, and the split is deliberate. Presentations are
// ordered — dragging one above another sets the sequence they will be given in,
// and dropping one onto a same-lesson pill merges the two. Check-ins sit in
// their own lane, unordered and grouped, because "sometime today" is all their
// position ever meant.
//
// They used to be stacked bands in one scrolling lane, which meant a day with
// six presentations hid its work checks below the fold — the two things a guide
// compares when planning a day were the two things he could not see at once.
//
// The whole day is still ONE drop zone. Splitting the drop target as well would
// invent a new way to fail: a presentation dropped on the work side would have
// to be either refused or silently re-aimed. Instead the lanes are layout only,
// and the delegate keeps routing by what was dragged, not by where it landed.

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

    /// One lane's width: exactly what a card had before the day split, so the
    /// pills read the same as they always did. The day is therefore about twice
    /// as wide and fewer of them fit on screen at once — the trade this split
    /// is worth, and the reason `WeekPlanSection.visibleDayCount` came down
    /// with it. Narrowing the cards instead was the first attempt and it made
    /// them unreadable.
    static let laneWidth: CGFloat = singleLaneWidth - zonePadding * 2
    static let laneGutter: CGFloat = 10
    /// What the column measured before it split, and what it goes back to when
    /// the Show filter leaves only one kind on screen.
    static let singleLaneWidth: CGFloat = 360
    static let zonePadding: CGFloat = 8

    /// Both lanes only when the Show filter is letting both kinds through —
    /// filtering to Presentations should not leave half the day permanently
    /// empty.
    var showsBothLanes: Bool {
        visibleKinds.showsPresentations && visibleKinds.showsWork
    }

    /// The presentation lane's own width, which the insertion indicator has to
    /// match: full width when it is the only lane, one lane when it is not.
    var presentationLaneWidth: CGFloat {
        showsBothLanes ? Self.laneWidth : Self.singleLaneWidth - Self.zonePadding * 2
    }

    private var columnWidth: CGFloat {
        showsBothLanes
            ? Self.laneWidth * 2 + Self.laneGutter + Self.zonePadding * 2
            : Self.singleLaneWidth
    }

    private var headerCountLabel: String {
        var parts: [String] = []
        let presentations = scheduledLessonsForDay.count
        if presentations > 0 {
            parts.append("\(presentations) pres")
        }
        let checkIns = visibleCheckInGroups.reduce(0) { $0 + $1.checkIns.count }
        if checkIns > 0 {
            parts.append("\(checkIns) check\(checkIns == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
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
                .frame(width: columnWidth)
                .frame(maxHeight: .infinity)
        }
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
            }

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: Self.laneGutter) {
                        if visibleKinds.showsPresentations {
                            presentationLane
                        }
                        if visibleKinds.showsWork {
                            checkInLane
                        }
                    }
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
