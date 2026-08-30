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

    let day: Date
    let allLessonAssignments: [CDLessonAssignment]
    let visibleKinds: CalendarKindFilter
    /// Already resolved and grouped for this day by the parent, which builds
    /// one lookup for the whole visible range.
    let checkInGroups: [CalendarCheckInGroup]
    let focusedPresentationID: UUID?
    let onClear: (CDLessonAssignment) -> Void
    let onSelect: (CDLessonAssignment) -> Void
    let onOpenCheckInGroup: (CalendarCheckInGroup) -> Void
    let onDropWorkCheckIn: (UUID, Date) -> Void
    let onDropWork: (UUID, Date) -> Void

    @State var itemFrames: [UUID: CGRect] = [:]
    @State var zoneSpaceID = UUID()
    @State var isTargeted: Bool = false
    @State var insertionIndex: Int?

    private struct FocusScrollTrigger: Equatable {
        let focusedID: UUID?
        let scheduledIDs: [UUID]
    }

    var scheduledLessonsForDay: [CDLessonAssignment] {
        guard visibleKinds.showsPresentations else { return [] }
        return allLessonAssignments.filter { la in
            guard let scheduled = la.scheduledFor, !la.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day)
        }
        // Swift's sort is not stable, and every legacy row still sits at
        // midnight — without a tiebreak the whole day is one tie and the order
        // reshuffles on any refetch or CloudKit merge.
        .sorted(by: LessonAssignmentOrdering.isOrderedBefore)
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

    // Students appearing on 2+ not-yet-presented lesson assignments on this day.
    // `scheduledLessonsForDay` already filters to `!la.isGiven`, so the count is pending-only.
    var doubleBookedStudentIDs: Set<UUID> {
        var counts: [UUID: Int] = [:]
        for assignment in scheduledLessonsForDay {
            for id in assignment.studentUUIDs {
                counts[id, default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value >= 2 }.keys)
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
                        itemFrames = frames
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
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
            onDropWorkCheckIn: onDropWorkCheckIn,
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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isTargeted ? 0.08 : 0.04))
            if isTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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

/// Reports each presentation card's frame so the drop delegate can compute an
/// insertion point. Top-level because the day column's content lives in an
/// extension in another file.
struct WeekDayPillFramePreference: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
