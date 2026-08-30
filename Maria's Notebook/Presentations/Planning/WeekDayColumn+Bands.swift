// WeekDayColumn+Bands.swift
// The two bands a day column draws: ordered presentations on top, grouped work
// check-ins below. Split out because the column is at SwiftLint's type-length
// limit — see WeekDayColumn.swift for the state they read.

import SwiftUI
import CoreData

extension WeekDayColumn {
    @ViewBuilder
    var presentationBand: some View {
        if !scheduledLessonsForDay.isEmpty {
            if !visibleCheckInGroups.isEmpty {
                bandLabel("Presenting")
            }
            ForEach(scheduledLessonsForDay, id: \.objectID) { la in
                presentationCard(la)
            }
        }
    }

    @ViewBuilder
    var checkInBand: some View {
        if !visibleCheckInGroups.isEmpty {
            if !scheduledLessonsForDay.isEmpty {
                bandLabel("Checking work")
                    .padding(.top, 4)
            }
            ForEach(visibleCheckInGroups) { group in
                checkInPill(group)
            }
        }
    }

    func bandLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
    }

    func presentationCard(_ la: CDLessonAssignment) -> some View {
        let laID = la.id ?? UUID()
        let dayDoubleBooked = doubleBookedStudentIDs
        return PresentationPlannerCard(
            snapshot: la.snapshot(),
            day: day,
            cachedLessons: nil,
            cachedStudents: nil,
            blockingWork: [:],
            doubleBookedStudentIDs: dayDoubleBooked
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
                doubleBookedStudentIDs: dayDoubleBooked
            )
            .opacity(UIConstants.OpacityConstants.nearSolid)
            // Drag previews don't inherit the app environment;
            // the card's @FetchRequests need a real context.
            .environment(\.managedObjectContext, viewContext)
        }
        .contextMenu {
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
        let payload = UnifiedCalendarDragPayload
            .workCheckIn(group.primary.id ?? UUID())
            .stringRepresentation

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

    @ViewBuilder
    var insertionIndicator: some View {
        if let idx = insertionIndex {
            GeometryReader { proxy in
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

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width - 24, height: 3)
                    .position(x: proxy.size.width / 2, y: indicatorY)
            }
            .allowsHitTesting(false)
        }
    }
}
