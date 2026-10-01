// WeekDayColumn+Bands.swift
// What a day column draws, top to bottom: its presentations in order, banded
// by half of the day, then its work checks. Split out because the column is at
// SwiftLint's type-length limit — see WeekDayColumn.swift for the state they
// read, and for why this is one list and not two lanes.

import SwiftUI
import CoreData

extension WeekDayColumn {
    /// The day's whole content. An empty day is a single dashed placeholder
    /// rather than an empty "Morning" and an empty "Checks": one obvious place
    /// to aim a drag, and no headings over nothing.
    @ViewBuilder
    var dayList: some View {
        let hasPresentations = !scheduledLessonsForDay.isEmpty
        let hasChecks = !visibleCheckInGroups.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            if !hasPresentations && !hasChecks {
                emptyDayPlaceholder
            }
            if hasPresentations {
                presentationList
            }
            if hasChecks {
                checksSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The day's presentations as one ordered list, with "Morning" and
    /// "Afternoon" printed above the first card of each half.
    ///
    /// The labels are only print. The list is still the single ordered run the
    /// drop delegate reorders and the half is still read off each card's time,
    /// so a card dropped under the last morning card is a morning lesson even
    /// though the "Afternoon" label is right beneath it — and the insertion bar
    /// is drawn above that label to say so (`insertionBarY`). A label appears
    /// only where the half changes, so only halves with cards get one.
    var presentationList: some View {
        // One walk over the day for the whole list. It used to be recomputed
        // inside every card, which meant walking the day once per card on it.
        let clashes = clashingStudentIDs
        let rows = Array(scheduledLessonsForDay.enumerated())
        let halves = scheduledLessonsForDay.map { half(of: $0) ?? .morning }
        // Lazy because a day can carry a classroom's worth of presentations
        // and every visible day builds its list.
        return LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.element.objectID) { index, la in
                if index == 0 || halves[index] != halves[index - 1] {
                    sectionLabel(halves[index].label)
                        .padding(.top, index == 0 ? 0 : 4)
                }
                presentationCard(la, clashing: clashes)
            }
        }
    }

    /// The day's work checks, one line each, after the presentations.
    var checksSection: some View {
        let count = visibleCheckInGroups.reduce(0) { $0 + $1.checkIns.count }
        return VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Checks", count: count)
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(visibleCheckInGroups) { group in
                    checkInPill(group)
                }
            }
        }
    }

    /// Given shape rather than a bare line of text, so it reads as somewhere
    /// to drop. It sits inside the column's one drop zone like everything else.
    var emptyDayPlaceholder: some View {
        Text("Drop a lesson or work here")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(UIConstants.OpacityConstants.veryFaint),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
    }

    func sectionLabel(_ text: String, count: Int? = nil) -> some View {
        HStack(spacing: 4) {
            Text(text.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
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
            period: period,
            // The Morning / Afternoon labels above the cards say it already.
            showsPeriodBadge: false
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
            dragPreview(la, doubleBooked: dayDoubleBooked, period: period)
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

    /// What follows the pointer while a card is dragged: the card at the
    /// column's width, so it does not change size on lift.
    func dragPreview(
        _ la: CDLessonAssignment,
        doubleBooked: Set<UUID>,
        period: DayPeriod?
    ) -> some View {
        PresentationPlannerCard(
            snapshot: la.snapshot(),
            day: day,
            cachedLessons: [],
            cachedStudents: [],
            blockingWork: [:],
            doubleBookedStudentIDs: doubleBooked,
            period: period,
            showsPeriodBadge: false
        )
        .frame(width: contentWidth)
        .opacity(UIConstants.OpacityConstants.nearSolid)
        // Drag previews don't inherit the app environment, and the card
        // still reads the context for the lesson's age and the day's
        // attendance — without one it traps at drag lift.
        .environment(\.managedObjectContext, viewContext)
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
                        .frame(width: contentWidth)
                        .opacity(UIConstants.OpacityConstants.almostOpaque)
                }
            } else {
                // Named from the group's batched lookup, like the grouped pill
                // above, so neither pill nor preview reads the context.
                WorkCheckInPill(group: group, isDulled: false) {
                    onOpenCheckInGroup(group)
                }
                .draggable(payload) {
                    WorkCheckInPill(group: group, isDulled: false)
                        .frame(width: contentWidth)
                        .opacity(UIConstants.OpacityConstants.almostOpaque)
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
    /// Built on every pass of the column, so the status items' row lookup
    /// waits in `WorkCheckPillStatusMenu` until the menu is shown.
    @ViewBuilder
    func checkInMenu(_ group: CalendarCheckInGroup) -> some View {
        Button {
            onOpenCheckInGroup(group)
        } label: {
            Label("Log Check…", systemImage: "square.and.pencil")
        }
        Divider()
        WorkCheckPillStatusMenu(group: group, actions: pillActions)
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
        // Read so a frame move mid-drag redraws the bar (the frames themselves
        // live in an unobserved box).
        // swiftlint:disable:next redundant_discardable_let
        let _ = itemFrameRevision
        // Nothing to insert into when the Show filter has hidden presentations.
        if let idx = insertionIndex, visibleKinds.showsPresentations {
            // Still a GeometryReader, though the width comes from the column
            // rather than the proxy: it is what gives the bar a full-size
            // container to be `.position`ed inside.
            GeometryReader { _ in
                // Each card's frame with the half it is in, in drawn order —
                // the same frames, sorted the same way, that the delegate turns
                // into `idx`, so the bar and the drop agree on the slot.
                let placed = scheduledLessonsForDay
                    .compactMap { la -> PlacedCard? in
                        guard let id = la.id, let frame = itemFrames[id] else { return nil }
                        return PlacedCard(frame: frame, half: half(of: la) ?? .morning)
                    }
                    .sorted { $0.frame.minY < $1.frame.minY }

                insertionBar(half: insertionHalf(at: idx))
                    .frame(width: contentWidth)
                    .position(x: columnWidth / 2, y: Self.insertionBarY(at: idx, among: placed))
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

// `WorkCheckPillActions`, what the pill menu can do, and the menu's status
// items live in WorkCheckPillMenu.swift.
