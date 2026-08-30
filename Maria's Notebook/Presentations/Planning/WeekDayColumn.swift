// WeekDayColumn.swift
// One day in the merged Lessons & Work calendar.
//
// Two bands, and the split is deliberate. Presentations are ordered — dragging
// one above another sets the sequence they will be given in, and dropping one
// onto a same-lesson pill merges the two. Check-ins sit below, unordered and
// grouped, because "sometime today" is all their position ever meant.
//
// Both bands accept drops. Before the two calendars merged, this column parsed
// a dropped work item and then discarded it, so the drag simply failed.

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

    private var isEmpty: Bool {
        scheduledLessonsForDay.isEmpty && visibleCheckInGroups.isEmpty
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
                .frame(width: 360)
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
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if isEmpty {
                            Text("Drag a presentation or work here")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(8)
                        } else {
                            presentationBand
                            checkInBand
                        }
                    }
                    .padding(8)
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
