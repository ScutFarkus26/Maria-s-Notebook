// PresentationsDayColumn.swift
// Day column component extracted from PresentationsView

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PresentationsDayColumn: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    let day: Date
    let allStudentLessons: [StudentLesson]
    let showWork: Bool
    let onClear: (StudentLesson) -> Void
    let onSelect: (StudentLesson) -> Void

    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var zoneSpaceID = UUID()
    @State private var isTargeted: Bool = false
    @State private var insertionIndex: Int? = nil

    private var scheduledLessonsForDay: [StudentLesson] {
        allStudentLessons.filter { sl in
            guard let scheduled = sl.scheduledFor, !sl.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day)
        }
        .sorted { ($0.scheduledFor ?? .distantPast) < ($1.scheduledFor ?? .distantPast) }
    }
    
    private var workItemsForDay: [WorkPlanItem] {
        let (start, end) = AppCalendar.dayRange(for: day)
        let descriptor = FetchDescriptor<WorkPlanItem>(
            predicate: #Predicate { $0.scheduledDate >= start && $0.scheduledDate < end }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Note: Cannot conform to Sendable because SwiftData models are not Sendable
    enum CalendarItem: Identifiable {
        case studentLesson(StudentLesson)
        case workPlanItem(WorkPlanItem)
        
        var id: UUID {
            switch self {
            case .studentLesson(let sl): return sl.id
            case .workPlanItem(let wpi): return wpi.id
            }
        }
        
        var sortDate: Date {
            switch self {
            case .studentLesson(let sl): return sl.scheduledFor ?? .distantPast
            case .workPlanItem(let wpi): return wpi.scheduledDate
            }
        }
    }
    
    private var allItemsForDay: [CalendarItem] {
        let lessons = scheduledLessonsForDay.map { CalendarItem.studentLesson($0) }
        let work = showWork ? workItemsForDay.map { CalendarItem.workPlanItem($0) } : []
        return (lessons + work).sorted { $0.sortDate < $1.sortDate }
    }
    
    private var uniqueStudentCount: Int {
        let allStudentIDs = scheduledLessonsForDay.flatMap { $0.studentIDs }
        return Set(allStudentIDs).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Day header
            HStack(spacing: 6) {
                Text(day.formatted(Date.FormatStyle().weekday(.abbreviated)))
                    .font(.caption.weight(.semibold))
                Text(day.formatted(Date.FormatStyle().day()))
                    .font(.headline.weight(.semibold))
                if uniqueStudentCount > 0 {
                    Text("\(uniqueStudentCount)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                }
                Spacer()
            }
            .padding(.horizontal, 6)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(isTargeted ? 0.08 : 0.04))
                if isTargeted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.7), lineWidth: 2)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if allItemsForDay.isEmpty {
                            Text("No plans yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(8)
                        } else {
                            ForEach(allItemsForDay) { item in
                                switch item {
                                case .studentLesson(let sl):
                                    StudentLessonPill(snapshot: sl.snapshot(), day: day, targetStudentLessonID: sl.id, showTimeBadge: false, enableMergeDrop: true)
                                        .onTapGesture { onSelect(sl) }
                                        .draggable(UnifiedCalendarDragPayload.studentLesson(sl.id).stringRepresentation) {
                                            StudentLessonPill(snapshot: sl.snapshot(), day: day, targetStudentLessonID: sl.id, showTimeBadge: false, enableMergeDrop: true).opacity(0.85)
                                        }
                                        .contextMenu {
                                            Button("Clear Schedule", systemImage: "xmark.circle") {
                                                onClear(sl)
                                            }
                                        }
                                        .background(
                                            GeometryReader { proxy in
                                                Color.clear.preference(
                                                    key: PillFramePreference.self,
                                                    value: [sl.id: proxy.frame(in: .named(zoneSpaceID))]
                                                )
                                            }
                                        )
                                case .workPlanItem(let wpi):
                                    WorkPlanItemPill(item: wpi, isDulled: true)
                                        .background(
                                            GeometryReader { proxy in
                                                Color.clear.preference(
                                                    key: PillFramePreference.self,
                                                    value: [wpi.id: proxy.frame(in: .named(zoneSpaceID))]
                                                )
                                            }
                                        )
                                }
                            }
                        }
                    }
                    .padding(8)
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
            .onDrop(of: [UTType.text], delegate: PresentationsDayColumnDropDelegate(
                calendar: calendar,
                modelContext: modelContext,
                allStudentLessons: allStudentLessons,
                day: day,
                getCurrentItems: { allItemsForDay },
                itemFramesProvider: { itemFrames },
                onTargetChange: { targeted in
                    withAnimation(.easeInOut(duration: 0.12)) { isTargeted = targeted }
                },
                onInsertionIndexChange: { idx in
                    if insertionIndex != idx {
                        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.85)) { insertionIndex = idx }
                    }
                }
            ))
            .frame(width: 360)
            .frame(maxHeight: .infinity)
        }
    }

    private struct PillFramePreference: PreferenceKey {
        static var defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }
}

// MARK: - Drop Delegate for day column
private struct PresentationsDayColumnDropDelegate: DropDelegate {
    let calendar: Calendar
    let modelContext: ModelContext
    let allStudentLessons: [StudentLesson]
    let day: Date
    let getCurrentItems: () -> [PresentationsDayColumn.CalendarItem]
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
        case .studentLesson(let id):
            applyStudentLessonDrop(id: id, locationY: locationY)
        case .workPlanItem(let id):
            applyWorkPlanItemDrop(id: id, locationY: locationY)
        }
    }
    
    @MainActor
    private func applyStudentLessonDrop(id: UUID, locationY: CGFloat) {
        let current = getCurrentItems()
        var ids = current.map { $0.id }
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
        let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: baseDate, calendar: calendar, spacingSeconds: 1)
        do {
            for itemID in ids {
                if let item = allStudentLessons.first(where: { $0.id == itemID }) {
                    item.setScheduledFor(timeMap[itemID], using: AppCalendar.shared)
                    #if DEBUG
                    item.checkInboxInvariant()
                    #endif
                }
            }
            try modelContext.save()
        } catch {
            #if DEBUG
            print("Presentations schedule save failed: \(error)")
            #endif
        }
    }
    
    @MainActor
    private func applyWorkPlanItemDrop(id: UUID, locationY: CGFloat) {
        // Fetch the WorkPlanItem
        let descriptor = FetchDescriptor<WorkPlanItem>(predicate: #Predicate<WorkPlanItem> { $0.id == id })
        guard let item = (try? modelContext.fetch(descriptor))?.first else { return }
        
        // Update its scheduled date to this day
        let normalized = AppCalendar.startOfDay(day)
        item.scheduledDate = normalized
        
        // Also update the associated WorkModel's dueAt
        if let workID = item.workID.asUUID {
            let workDescriptor = FetchDescriptor<WorkModel>(predicate: #Predicate<WorkModel> { $0.id == workID })
            if let work = (try? modelContext.fetch(workDescriptor))?.first {
                work.dueAt = normalized
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("Work item schedule save failed: \(error)")
            #endif
        }
    }

    private func baseDateForDay(day: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: 9, to: startOfDay) ?? startOfDay
    }
}
