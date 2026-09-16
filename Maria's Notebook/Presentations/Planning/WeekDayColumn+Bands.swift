// WeekDayColumn+Bands.swift
// The two lanes a day column draws, side by side: ordered presentations on the
// left, grouped work check-ins on the right. Split out because the column is at
// SwiftLint's type-length limit — see WeekDayColumn.swift for the state they
// read.
//
// Each lane keeps its header and its own placeholder even when empty. A lane
// that vanished when it had nothing in it would make the day reflow every time
// the last check-in was cleared, and would leave no target to aim a drag at.

import SwiftUI
import CoreData

extension WeekDayColumn {
    var presentationLane: some View {
        // One walk over the day for the whole lane. It used to be recomputed
        // inside every card, which meant walking the day once per card on it.
        let clashes = clashingStudentIDs
        return lane(
            title: "Presenting",
            count: scheduledLessonsForDay.count,
            placeholder: "Drag a presentation here"
        ) {
            ForEach(scheduledLessonsForDay, id: \.objectID) { la in
                presentationCard(la, clashing: clashes)
            }
        }
    }

    var checkInLane: some View {
        lane(
            title: "Checking work",
            count: visibleCheckInGroups.reduce(0) { $0 + $1.checkIns.count },
            placeholder: "Drag work here"
        ) {
            ForEach(visibleCheckInGroups) { group in
                checkInPill(group)
            }
        }
    }

    /// One lane: a header that stays put, then whatever the lane holds.
    ///
    /// Lazy inside, because a day can carry a classroom's worth of either kind
    /// and both lanes are built for every visible day.
    @ViewBuilder
    func lane<Content: View>(
        title: String,
        count: Int,
        placeholder: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            laneHeader(title, count: count)
            if count == 0 {
                // Given shape rather than a bare line of text: the lanes are
                // top-aligned, so an empty one next to a full one would
                // otherwise be a sentence floating beside a column of cards,
                // with nothing that reads as somewhere to drop.
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                Color.primary.opacity(UIConstants.OpacityConstants.veryFaint),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    )
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    content()
                }
            }
        }
        // Fixed when the lanes share the day, so the two halves line up down
        // the whole strip; free when a lane is alone, so it keeps the full
        // width the column always had.
        .frame(
            width: showsBothLanes ? WeekDayColumn.laneWidth : nil,
            alignment: .leading
        )
        .frame(maxWidth: showsBothLanes ? WeekDayColumn.laneWidth : .infinity, alignment: .leading)
    }

    func laneHeader(_ text: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(text.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
    }

    func presentationCard(
        _ la: CDLessonAssignment,
        clashing: [DayPeriod: Set<UUID>]
    ) -> some View {
        let laID = la.id ?? UUID()
        let period = half(of: la)
        // This card's own half and no other: a child doubled up in the morning
        // is not doubled up on the one afternoon lesson she also has.
        let dayDoubleBooked = clashing[period ?? .morning] ?? []
        return PresentationPlannerCard(
            snapshot: la.snapshot(),
            day: day,
            cachedLessons: lessons,
            cachedStudents: students,
            blockingWork: [:],
            doubleBookedStudentIDs: dayDoubleBooked,
            period: period
        )
        .id(laID)
        .overlay {
            if focusedPresentationID == laID {
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2.5)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 6)
            }
        }
        .onTapGesture { onSelect(la) }
        .draggable(UnifiedCalendarDragPayload.presentation(laID).stringRepresentation) {
            PresentationPlannerCard(
                snapshot: la.snapshot(),
                day: day,
                cachedLessons: [],
                cachedStudents: [],
                blockingWork: [:],
                doubleBookedStudentIDs: dayDoubleBooked,
                period: period
            )
            .opacity(UIConstants.OpacityConstants.nearSolid)
            // Drag previews don't inherit the app environment, and the card
            // still reads the context for the lesson's age and the day's
            // attendance — without one it traps at drag lift.
            .environment(\.managedObjectContext, viewContext)
        }
        .contextMenu {
            halfPicker(for: la)
            Divider()
            ShowInChecklistButton(lessonID: la.resolvedLessonID, context: viewContext)
            Button("Clear Schedule", systemImage: "xmark.circle") {
                onClear(la)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WeekDayPillFramePreference.self,
                    value: [laID: proxy.frame(in: .named(zoneSpaceID))]
                )
            }
        )
    }

    @ViewBuilder
    func checkInPill(_ group: CalendarCheckInGroup) -> some View {
        // Every check-in under the pill, not just the one it is keyed on — see
        // `CalendarCheckInGroup.dragPayload`.
        let payload = group.dragPayload
        let isRescheduling = Binding(
            get: { reschedulingGroupID == group.id },
            set: { if !$0 { reschedulingGroupID = nil } }
        )

        Group {
            if group.isGrouped {
                GroupedWorkCheckInPill(sequence: group) {
                    onOpenCheckInGroup(group)
                }
                .draggable(payload) {
                    GroupedWorkCheckInPill(sequence: group)
                        .opacity(UIConstants.OpacityConstants.almostOpaque)
                }
            } else {
                WorkCheckInPill(checkIn: group.primary, isDulled: false) {
                    onOpenCheckInGroup(group)
                }
                .draggable(payload) {
                    WorkCheckInPill(checkIn: group.primary, isDulled: false)
                        .opacity(UIConstants.OpacityConstants.almostOpaque)
                        .environment(\.managedObjectContext, viewContext)
                }
            }
        }
        .contextMenu { checkInMenu(group) }
        .popover(isPresented: isRescheduling) {
            WorkCheckDayPicker(count: group.checkIns.count) { day in
                reschedulingGroupID = nil
                onDropWorkCheckIns(group.checkIns.compactMap(\.id), day)
            } onCancel: {
                reschedulingGroupID = nil
            }
        }
    }

    /// The pill's right-click menu. Logging a status here is the same write
    /// the sheet makes, without the note; the pill leaves the strip either way.
    @ViewBuilder
    func checkInMenu(_ group: CalendarCheckInGroup) -> some View {
        Button {
            onOpenCheckInGroup(group)
        } label: {
            Label("Log Check…", systemImage: "square.and.pencil")
        }
        Divider()
        WorkLogStatusMenu(
            targets: pillActions.rows(group),
            children: pillActions.children(group)
        ) { rows, status in
            pillActions.log(group, rows, status)
        }
        Divider()
        Menu {
            let ids = group.checkIns.compactMap(\.id)
            Button("Today") { onDropWorkCheckIns(ids, AppCalendar.startOfDay(Date())) }
            Button("Tomorrow") {
                onDropWorkCheckIns(ids, AppCalendar.addingDays(1, to: AppCalendar.startOfDay(Date())))
            }
            Divider()
            Button("Pick a Day…") { reschedulingGroupID = group.id }
        } label: {
            Label("Reschedule", systemImage: "calendar")
        }
        if !group.isGrouped, let workID = group.primary.workID.asUUID {
            Divider()
            Button {
                pillActions.openWork(workID)
            } label: {
                Label("Open Work", systemImage: "arrow.forward.circle")
            }
        }
    }

    @ViewBuilder
    var insertionIndicator: some View {
        // Nothing to insert into when the Show filter has hidden presentations,
        // and the bar would otherwise draw across the work lane.
        if let idx = insertionIndex, visibleKinds.showsPresentations {
            // Still a GeometryReader, though the width now comes from the lane
            // rather than the proxy: it is what gives the bar a full-size
            // container to be `.position`ed inside.
            GeometryReader { _ in
                let sortedFrames = scheduledLessonsForDay
                    .compactMap { la -> CGRect? in la.id.flatMap { itemFrames[$0] } }
                    .sorted { $0.minY < $1.minY }

                let indicatorY: CGFloat = {
                    if sortedFrames.isEmpty {
                        return 16
                    } else if idx < sortedFrames.count {
                        return sortedFrames[idx].minY - 3
                    } else if let lastFrame = sortedFrames.last {
                        return lastFrame.maxY + 3
                    } else {
                        return 16
                    }
                }()

                // Over the presentation lane only — the ordering it previews
                // has no meaning on the work side, and a full-width bar would
                // claim it does.
                let laneWidth = presentationLaneWidth
                insertionBar(half: insertionHalf(at: idx))
                    .frame(width: max(laneWidth - 8, 0))
                    .position(x: 8 + laneWidth / 2, y: indicatorY)
            }
            .allowsHitTesting(false)
        }
    }

    /// The insertion bar, tagged with the half the drop will land in.
    ///
    /// The tag is the rule made visible: a lesson dropped here takes the half
    /// of the card above it, and without saying so the calendar would be
    /// quietly deciding morning or afternoon on the guide's behalf.
    func insertionBar(half: DayPeriod) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(Color.accentColor)
                .frame(height: 3)
            Text(half.abbreviation)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

/// What a check-in pill's right-click menu can do, handed down from
/// `WeekPlanSection`, which owns the check-in lookup, the save and the toast.
struct WorkCheckPillActions {
    /// The rows under a pill, one per child.
    let rows: (CalendarCheckInGroup) -> [CDWorkModel]
    /// The same rows named for per-child submenus.
    let children: (CalendarCheckInGroup) -> [WorkLogStatusMenu.Child]
    /// Logs a status on some of a pill's rows for the pill's day.
    let log: (CalendarCheckInGroup, [CDWorkModel], WorkStatus) -> Void
    let openWork: (UUID) -> Void
}
