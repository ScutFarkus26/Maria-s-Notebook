// WeekDayColumn.swift
// Single day column in the Week Plan calendar.

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

struct WeekDayColumn: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar

    let day: Date
    let allLessonAssignments: [CDLessonAssignment]
    let showWork: Bool
    // OPTIMIZATION: Accept pre-fetched work items from parent
    let preloadedWorkItems: [CDWorkCheckIn]
    let focusedPresentationID: UUID?
    let onClear: (CDLessonAssignment) -> Void
    let onSelect: (CDLessonAssignment) -> Void

    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var zoneSpaceID = UUID()
    @State private var isTargeted: Bool = false
    @State private var insertionIndex: Int?

    private struct FocusScrollTrigger: Equatable {
        let focusedID: UUID?
        let scheduledIDs: [UUID]
    }

    private var scheduledLessonsForDay: [CDLessonAssignment] {
        allLessonAssignments.filter { la in
            guard let scheduled = la.scheduledFor, !la.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day)
        }
        .sorted { ($0.scheduledFor ?? .distantPast) < ($1.scheduledFor ?? .distantPast) }
    }

    private var focusScrollTrigger: FocusScrollTrigger {
        FocusScrollTrigger(
            focusedID: focusedPresentationID,
            scheduledIDs: scheduledLessonsForDay.compactMap(\.id)
        )
    }

    // Students appearing on 2+ not-yet-presented lesson assignments on this day.
    // `scheduledLessonsForDay` already filters to `!la.isGiven`, so the count is pending-only.
    private var doubleBookedStudentIDs: Set<UUID> {
        var counts: [UUID: Int] = [:]
        for assignment in scheduledLessonsForDay {
            for id in assignment.studentUUIDs {
                counts[id, default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value >= 2 }.keys)
    }

    // Phase 6: WorkPlanItem removed from schema - migrated to CDWorkCheckIn
    // OPTIMIZATION: Filter pre-loaded work items instead of fetching from database
    // This eliminates per-column database queries (33 queries -> 0 queries)
    private var workItemsForDay: [CDWorkCheckIn] {
        let (start, end) = AppCalendar.dayRange(for: day)
        return preloadedWorkItems.filter { ($0.date ?? .distantPast) >= start && ($0.date ?? .distantPast) < end }
    }

    /// CDNote: Cannot conform to Sendable because SwiftData models are not Sendable
    enum CalendarItem: Identifiable {
        case lessonAssignment(CDLessonAssignment)
        case workCheckIn(CDWorkCheckIn) // Phase 6: renamed from workPlanItem

        var id: UUID {
            switch self {
            case .lessonAssignment(let la): return la.id ?? UUID()
            case .workCheckIn(let wci): return wci.id ?? UUID()
            }
        }

        var sortDate: Date {
            switch self {
            case .lessonAssignment(let la): return la.scheduledFor ?? .distantPast
            case .workCheckIn(let wci): return wci.date ?? .distantPast
            }
        }
    }

    private var allItemsForDay: [CalendarItem] {
        let lessons = scheduledLessonsForDay.map { CalendarItem.lessonAssignment($0) }
        let work = showWork ? workItemsForDay.map { CalendarItem.workCheckIn($0) } : []
        return (lessons + work).sorted { $0.sortDate < $1.sortDate }
    }

    private var plannedCount: Int {
        scheduledLessonsForDay.count
    }

    private var uniqueStudentCount: Int {
        var seen = Set<UUID>()
        for assignment in scheduledLessonsForDay {
            for id in assignment.studentUUIDs { seen.insert(id) }
        }
        return seen.count
    }

    private var plannedLabel: String {
        let s = "\(uniqueStudentCount) student" + (uniqueStudentCount == 1 ? "" : "s")
        let p = "\(plannedCount) presentation" + (plannedCount == 1 ? "" : "s")
        return "\(s), \(p)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Day header — weekday, date, planned count
            HStack(spacing: 6) {
                Text(day.formatted(Date.FormatStyle().weekday(.abbreviated)))
                    .font(.caption.weight(.semibold))
                Text(day.formatted(Date.FormatStyle().day()))
                    .font(.headline.weight(.semibold))
                Spacer()
                if plannedCount > 0 {
                    Text(plannedLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)

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
                            if allItemsForDay.isEmpty {
                                Text("Drag a presentation here")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                            } else {
                                ForEach(allItemsForDay) { item in
                                    switch item {
                                    case .lessonAssignment(let la):
                                        let laID = la.id ?? UUID()
                                        let dayDoubleBooked = doubleBookedStudentIDs
                                        PresentationPlannerCard(
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
                                                    RoundedRectangle(
                                                        cornerRadius: UIConstants.CornerRadius.medium,
                                                        style: .continuous
                                                    )
                                                    .stroke(Color.accentColor, lineWidth: 2.5)
                                                    .shadow(
                                                        color: Color.accentColor.opacity(0.4),
                                                        radius: 6
                                                    )
                                                }
                                            }
                                            .onTapGesture { onSelect(la) }
                                            .draggable(
                                                UnifiedCalendarDragPayload.presentation(laID).stringRepresentation
                                            ) {
                                                PresentationPlannerCard(
                                                    snapshot: la.snapshot(),
                                                    day: day,
                                                    cachedLessons: [],
                                                    cachedStudents: [],
                                                    blockingWork: [:],
                                                    doubleBookedStudentIDs: dayDoubleBooked
                                                ).opacity(UIConstants.OpacityConstants.nearSolid)
                                            }
                                            .contextMenu {
                                                Button("Clear Schedule", systemImage: "xmark.circle") {
                                                    onClear(la)
                                                }
                                            }
                                            .background(
                                                GeometryReader { proxy in
                                                    Color.clear.preference(
                                                        key: PillFramePreference.self,
                                                        value: [laID: proxy.frame(in: .named(zoneSpaceID))]
                                                    )
                                                }
                                            )
                                    case .workCheckIn(let wci):
                                        let wciID = wci.id ?? UUID()
                                        WorkCheckInPill(checkIn: wci, isDulled: true)
                                            .id(wciID)
                                            .background(
                                                GeometryReader { proxy in
                                                    Color.clear.preference(
                                                        key: PillFramePreference.self,
                                                        value: [wciID: proxy.frame(in: .named(zoneSpaceID))]
                                                    )
                                                }
                                            )
                                    }
                                }
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

                // Insertion indicator overlay
                if let idx = insertionIndex {
                    GeometryReader { proxy in
                        let sortedFrames = allItemsForDay.compactMap { item -> (UUID, CGRect)? in
                            guard let rect = itemFrames[item.id] else { return nil }
                            return (item.id, rect)
                        }.sorted { $0.1.minY < $1.1.minY }

                        let indicatorY: CGFloat = {
                            if sortedFrames.isEmpty {
                                return 16
                            } else if idx < sortedFrames.count {
                                return sortedFrames[idx].1.minY - 3
                            } else if let lastFrame = sortedFrames.last {
                                return lastFrame.1.maxY + 3
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
            .coordinateSpace(name: zoneSpaceID)
            .onPreferenceChange(PillFramePreference.self) { frames in
                // Defer state update to next run loop to avoid layout recursion
                // PreferenceKey updates happen during layout, so we must defer state changes
                Task { @MainActor in
                    itemFrames = frames
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onDrop(of: [UTType.text], delegate: WeekDayColumnDropDelegate(
                calendar: calendar,
                viewContext: viewContext,
                allLessonAssignments: allLessonAssignments,
                day: day,
                getCurrentItems: { allItemsForDay },
                itemFramesProvider: { itemFrames },
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
            ))
            .frame(width: 360)
            .frame(maxHeight: .infinity)
        }
    }

    private struct PillFramePreference: PreferenceKey {
        nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }
}

// MARK: - Drop Delegate for day column
private struct WeekDayColumnDropDelegate: DropDelegate {
    private static let logger = Logger.presentations
    let calendar: Calendar
    let viewContext: NSManagedObjectContext
    let allLessonAssignments: [CDLessonAssignment]
    let day: Date
    let getCurrentItems: () -> [WeekDayColumn.CalendarItem]
    let itemFramesProvider: () -> [UUID: CGRect]
    let onTargetChange: (Bool) -> Void
    let onInsertionIndexChange: (Int?) -> Void

    func dropEntered(info: DropInfo) {
        onTargetChange(true)
        onInsertionIndexChange(computeIndex(info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onInsertionIndexChange(computeIndex(info))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onTargetChange(false)
        onInsertionIndexChange(nil)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        onTargetChange(false)
        onInsertionIndexChange(nil)
        let providers = info.itemProviders(for: [UTType.text])
        return performDropFromProvidersAsync(providers: providers, location: info.location)
    }

    private func computeIndex(_ info: DropInfo) -> Int? {
        let current = getCurrentItems()
        let frames = itemFramesProvider()
        let dict: [UUID: CGRect] = Dictionary(
            current.compactMap { item -> (UUID, CGRect)? in
                if let rect = frames[item.id] { return (item.id, rect) }
                return nil
            },
            uniquingKeysWith: { first, _ in first }
        )
        return PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: dict)
    }

    private func performDropFromProvidersAsync(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let payloadString = (ns as String).trimmed()
            guard let payload = UnifiedCalendarDragPayload.parse(payloadString) else { return }
            Task { @MainActor in
                applyDrop(payload: payload, locationY: location.y)
            }
        }
        return true
    }

    @MainActor
    private func applyDrop(payload: UnifiedCalendarDragPayload, locationY: CGFloat) {
        switch payload {
        case .presentation(let id):
            applyPresentationDrop(id: id, locationY: locationY)
        case .workCheckIn, .work, .yearPlanEntry:
            // Work items, check-ins, and year plan entries are not supported in presentations view
            break
        }
    }

    @MainActor
    private func applyPresentationDrop(id: UUID, locationY: CGFloat) {
        let current = getCurrentItems()

        // Check if the drop landed on a pill for the same lesson — merge instead of reorder
        if let source = allLessonAssignments.first(where: { $0.id == id }), !source.isGiven {
            let frames = itemFramesProvider()
            let scheduledLessons = current.compactMap { item -> CDLessonAssignment? in
                if case .lessonAssignment(let la) = item { return la }
                return nil
            }
            if let targetSL = scheduledLessons.first(where: { sl in
                guard let slID = sl.id, slID != id, !sl.isGiven,
                      sl.resolvedLessonID == source.resolvedLessonID,
                      let frame = frames[slID] else { return false }
                return locationY >= frame.minY && locationY <= frame.maxY
            }) {
                PresentationMergeService.merge(
                    sourceID: id,
                    targetID: targetSL.id ?? UUID(),
                    context: viewContext
                )
                return
            }
        }

        var ids = current.map(\.id)
        if let existing = ids.firstIndex(of: id) { ids.remove(at: existing) }
        let frames = itemFramesProvider()
        let dict: [UUID: CGRect] = Dictionary(
            current.compactMap { item -> (UUID, CGRect)? in
                if let rect = frames[item.id] { return (item.id, rect) }
                return nil
            },
            uniquingKeysWith: { first, _ in first }
        )
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: locationY, frames: dict)
        let bounded = max(0, min(insertionIndex, ids.count))
        ids.insert(id, at: bounded)
        let baseDate = baseDateForDay(day: day, calendar: calendar)
        let timeMap = PlanningDropUtils.assignSequentialTimes(
            ids: ids, base: baseDate, calendar: calendar, spacingSeconds: 1
        )
        do {
            for itemID in ids {
                if let item = allLessonAssignments.first(where: { $0.id == itemID }) {
                    item.setScheduledFor(timeMap[itemID], using: AppCalendar.shared)
                }
            }
            try viewContext.save()

            // Auto-populate year plan entries for the dropped presentation's sequence
            if let droppedItem = allLessonAssignments.first(where: { $0.id == id }),
               droppedItem.state == .scheduled {
                Task {
                    await SequenceAutoPopulateService.autoPopulateSequence(
                        for: droppedItem,
                        scheduledDate: droppedItem.scheduledFor ?? day,
                        context: viewContext
                    )
                }
            }
        } catch {
            Self.logger.warning("Presentations schedule save failed: \(error)")
        }
    }

    private func baseDateForDay(day: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: 9, to: startOfDay) ?? startOfDay
    }
}
