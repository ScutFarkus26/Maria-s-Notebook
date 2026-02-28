import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

struct AgendaSlot: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    let allLessonAssignments: [LessonAssignment]
    let day: Date
    let period: DayPeriod
    let onSelectLesson: (LessonAssignment) -> Void
    let onQuickActions: (LessonAssignment) -> Void
    let onPlanNext: (LessonAssignment) -> Void
    let onMoveToInbox: (LessonAssignment) -> Void
    let onMoveStudents: (LessonAssignment) -> Void

    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var zoneSpaceID = UUID()
    @State private var isTargeted: Bool = false
    @State private var insertionIndex: Int?

    private var scheduledLessonsForSlot: [LessonAssignment] {
        allLessonAssignments.filter { la in
            guard let scheduled = la.scheduledFor, !la.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day) && isInSlot(scheduled, period: period)
        }
        .sorted { ($0.scheduledFor ?? .distantPast) < ($1.scheduledFor ?? .distantPast) }
    }

    init(
        allLessonAssignments: [LessonAssignment],
        day: Date,
        period: DayPeriod,
        onSelectLesson: @escaping (LessonAssignment) -> Void,
        onQuickActions: @escaping (LessonAssignment) -> Void,
        onPlanNext: @escaping (LessonAssignment) -> Void,
        onMoveToInbox: @escaping (LessonAssignment) -> Void,
        onMoveStudents: @escaping (LessonAssignment) -> Void
    ) {
        self.allLessonAssignments = allLessonAssignments
        self.day = day
        self.period = period
        self.onSelectLesson = onSelectLesson
        self.onQuickActions = onQuickActions
        self.onPlanNext = onPlanNext
        self.onMoveToInbox = onMoveToInbox
        self.onMoveStudents = onMoveStudents
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isTargeted ? 0.04 : 0.02))

            if isTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 3)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 8) {
                if scheduledLessonsForSlot.isEmpty {
                    Text("No plans yet")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                } else {
                    ForEach(Array(scheduledLessonsForSlot.enumerated()), id: \.element.id) { index, la in
                        lessonPillView(for: la)
                    }
                }
            }
            .padding(12)
            .overlay(
                GeometryReader { proxy in
                    if let idx = insertionIndex {
                        let frames: [(UUID, CGRect)] = scheduledLessonsForSlot.compactMap { item in
                            if let rect = itemFrames[item.id] { return (item.id, rect) }
                            return nil
                        }.sorted { $0.1.minY < $1.1.minY }

                        if frames.isEmpty {
                            // Empty slot - show indicator at top
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width - 24, height: 3)
                                .position(x: proxy.size.width / 2, y: 12)
                        } else {
                            // Show indicator at insertion position
                            let y: CGFloat = {
                                if idx < frames.count {
                                    return frames[idx].1.minY
                                } else if let lastFrame = frames.last {
                                    return lastFrame.1.maxY + 8
                                } else {
                                    return 12
                                }
                            }()
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width - 24, height: 3)
                                .position(x: proxy.size.width / 2, y: y)
                        }
                    }
                }
            )
        }
        .coordinateSpace(name: zoneSpaceID)
        .onPreferenceChange(PillFramePreference.self) { frames in
            // Defer state update to next run loop to avoid layout recursion
            // PreferenceKey updates happen during layout, so we must defer state changes
            Task { @MainActor in
                itemFrames = frames
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDrop(of: [UTType.text], delegate: AgendaSlotDropDelegate(
            calendar: calendar,
            modelContext: modelContext,
            allLessonAssignments: allLessonAssignments,
            day: day,
            period: period,
            getCurrent: { scheduledLessonsForSlot },
            itemFramesProvider: { itemFrames },
            onTargetChange: { targeted in
                isTargeted = targeted
            },
            onInsertionIndexChange: { idx in
                insertionIndex = idx
            }
        ))
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func lessonPillView(for la: LessonAssignment) -> some View {
        PresentationPill(
            snapshot: la.snapshot(),
            day: day,
            sourceLessonAssignmentID: la.id,
            targetLessonAssignmentID: la.id,
            enableMergeDrop: true
        )
        .draggable(la.id.uuidString) {
            // Custom drag preview
            PresentationPill(
                snapshot: la.snapshot(),
                day: day,
                sourceLessonAssignmentID: la.id,
                targetLessonAssignmentID: la.id
            )
            .opacity(0.8)
        }
        .onTapGesture {
            onSelectLesson(la)
        }
        .contextMenu {
            Button {
                onQuickActions(la)
            } label: {
                Label("Quick Actions…", systemImage: "bolt")
            }

            Button {
                onPlanNext(la)
            } label: {
                Label("Plan Next Lesson in Group", systemImage: SFSymbol.Time.calendarBadgePlus)
            }

            Button {
                onSelectLesson(la)
            } label: {
                Label("Open Details", systemImage: SFSymbol.Status.infoCircle)
            }

            Button {
                onMoveStudents(la)
            } label: {
                Label("Move Students…", systemImage: "person.2.arrow.right")
            }

            Button {
                onMoveToInbox(la)
            } label: {
                Label("Move to Inbox", systemImage: SFSymbol.Document.tray)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PillFramePreference.self,
                    value: [la.id: proxy.frame(in: .named(zoneSpaceID))]
                )
            }
        )
    }

    private func isInSlot(_ date: Date, period: DayPeriod) -> Bool {
        let hour = calendar.component(.hour, from: date)
        switch period {
        case .morning: return hour < 12
        case .afternoon: return hour >= 12
        }
    }

    @MainActor static func baseDateForSlot(day: Date, period: DayPeriod, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        let hour: Int = (period == .morning) ? 9 : 14
        return calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
    }
}

struct AgendaSlotDropDelegate: DropDelegate {
    private static let logger = Logger.planning
    let calendar: Calendar
    let modelContext: ModelContext
    let allLessonAssignments: [LessonAssignment]
    let day: Date
    let period: DayPeriod
    let getCurrent: () -> [LessonAssignment]
    let itemFramesProvider: () -> [UUID: CGRect]
    let onTargetChange: (Bool) -> Void
    let onInsertionIndexChange: (Int?) -> Void

    init(
        calendar: Calendar,
        modelContext: ModelContext,
        allLessonAssignments: [LessonAssignment],
        day: Date,
        period: DayPeriod,
        getCurrent: @escaping () -> [LessonAssignment],
        itemFramesProvider: @escaping () -> [UUID: CGRect],
        onTargetChange: @escaping (Bool) -> Void,
        onInsertionIndexChange: @escaping (Int?) -> Void
    ) {
        self.calendar = calendar
        self.modelContext = modelContext
        self.allLessonAssignments = allLessonAssignments
        self.day = day
        self.period = period
        self.getCurrent = getCurrent
        self.itemFramesProvider = itemFramesProvider
        self.onTargetChange = onTargetChange
        self.onInsertionIndexChange = onInsertionIndexChange
    }

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
        return info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        onTargetChange(false)
        onInsertionIndexChange(nil)
        let providers = info.itemProviders(for: [UTType.text])
        return performDropFromProvidersAsync(providers: providers, location: info.location)
    }

    nonisolated func performDropFromProviders(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first else { return false }
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        _ = provider.loadObject(ofClass: NSString.self) { reading, _ in
            defer { semaphore.signal() }
            guard let ns = reading as? NSString else { return }
            let payload = ns as String
            if let id = UUID(uuidString: payload.trimmed()) {
                Task { @MainActor in
                    let calendar = self.calendar
                    let day = self.day
                    let period = self.period
                    let modelContext = self.modelContext
                    let allLessonAssignments = self.allLessonAssignments
                    let currentLessons = self.getCurrent()
                    var ids = currentLessons.map { $0.id }
                    if let existing = ids.firstIndex(of: id) { ids.remove(at: existing) }
                    let frames = self.itemFramesProvider()
                    let dict: [UUID: CGRect] = Dictionary(
                        currentLessons.compactMap { item -> (UUID, CGRect)? in
                            if let rect = frames[item.id] { return (item.id, rect) }
                            return nil
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: dict)
                    let bounded = max(0, min(insertionIndex, ids.count))
                    ids.insert(id, at: bounded)
                    let baseDate = AgendaSlot.baseDateForSlot(day: day, period: period, calendar: calendar)
                    let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: baseDate, calendar: calendar, spacingSeconds: 1)
                    for id in ids {
                        if let item = allLessonAssignments.first(where: { $0.id == id }) {
                            item.setScheduledFor(timeMap[id], using: AppCalendar.shared)
                            // Auto-enroll students in track if lesson belongs to a track
                            if let lesson = item.lesson {
                                GroupTrackService.autoEnrollInTrackIfNeeded(
                                    lesson: lesson,
                                    studentIDs: item.studentIDs,
                                    modelContext: modelContext
                                )
                            }
                        }
                    }
                    result = true
                }
            }
        }
        semaphore.wait()
        return result
    }

    nonisolated func performDropFromProvidersAsync(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else {
                return
            }
            let payload = ns as String

            Task { @MainActor in
                let modelContext = self.modelContext
                let allLessonAssignments = self.allLessonAssignments
                let calendar = self.calendar
                let day = self.day
                let period = self.period
                let currentLessons = self.getCurrent()
                let currentFrames = self.itemFramesProvider()

                // First, handle student-to-slot or student-to-inbox payloads
                if payload.hasPrefix("STUDENT_TO_INBOX:") || payload.hasPrefix("STUDENT_TO_SLOT:") {
                    let parts = payload.split(separator: ":")
                    if parts.count == 4,
                       let srcID = UUID(uuidString: String(parts[1])),
                       let lessonID = UUID(uuidString: String(parts[2])),
                       let studentID = UUID(uuidString: String(parts[3])) {

                        var ids = currentLessons.map { $0.id }
                        let frames = currentFrames
                        let dict: [UUID: CGRect] = Dictionary(
                            currentLessons.compactMap { item -> (UUID, CGRect)? in
                                if let rect = frames[item.id] { return (item.id, rect) }
                                return nil
                            },
                            uniquingKeysWith: { first, _ in first }
                        )
                        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: dict)

                        let existing = allLessonAssignments.first(where: { la in
                            let matchesLesson = la.resolvedLessonID == lessonID
                            let isUnscheduled = la.scheduledFor == nil
                            let isNotGiven = !la.isGiven
                            let matchesStudentSet = Set(la.resolvedStudentIDs) == Set([studentID])
                            return matchesLesson && isUnscheduled && isNotGiven && matchesStudentSet
                        })
                        let targetLA: LessonAssignment
                        if let ex = existing {
                            targetLA = ex
                        } else {
                            let new = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [studentID])
                            var lessonFetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
                            lessonFetch.fetchLimit = 1
                            var studentFetch = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
                            studentFetch.fetchLimit = 1
                            do {
                                new.lesson = try modelContext.fetch(lessonFetch).first
                            } catch {
                                Self.logger.warning("Failed to fetch lesson: \(error)")
                            }
                            do {
                                if let s = try modelContext.fetch(studentFetch).first {
                                    new.students = [s]
                                }
                            } catch {
                                Self.logger.warning("Failed to fetch student: \(error)")
                            }
                            modelContext.insert(new)
                            targetLA = new
                        }

                        ids.removeAll(where: { $0 == targetLA.id })
                        let boundedIndex = max(0, min(insertionIndex, ids.count))
                        ids.insert(targetLA.id, at: boundedIndex)
                        let baseDate = AgendaSlot.baseDateForSlot(day: day, period: period, calendar: calendar)
                        let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: baseDate, calendar: calendar, spacingSeconds: 1)

                        for id in ids {
                            if let item = allLessonAssignments.first(where: { $0.id == id }) { item.setScheduledFor(timeMap[id], using: AppCalendar.shared) }
                            if id == targetLA.id { targetLA.setScheduledFor(timeMap[id], using: AppCalendar.shared) }
                        }

                        if let src = allLessonAssignments.first(where: { $0.id == srcID }) {
                            src.studentIDs.removeAll { $0 == studentID.uuidString }
                            src.students.removeAll { $0.id == studentID }
                            if src.studentIDs.isEmpty { modelContext.delete(src) }
                        }
                        do {
                            try modelContext.save()
                        } catch {
                            Self.logger.warning("Failed to save context after student move: \(error)")
                        }

                        // Auto-enroll students in track if lesson belongs to a track
                        if let lesson = targetLA.lesson {
                            GroupTrackService.autoEnrollInTrackIfNeeded(
                                lesson: lesson,
                                studentIDs: targetLA.studentIDs,
                                modelContext: modelContext
                            )
                        }
                        return
                    }
                }

                // Fallback: treat as a plain LessonAssignment ID
                if let id = UUID(uuidString: payload.trimmed()) {
                    // Check if the drop landed on a pill for the same lesson — merge instead of reorder
                    if let source = allLessonAssignments.first(where: { $0.id == id }), !source.isGiven {
                        let frames = currentFrames
                        let dropY = location.y
                        if let targetLA = currentLessons.first(where: { la in
                            guard la.id != id, !la.isGiven,
                                  la.resolvedLessonID == source.resolvedLessonID,
                                  let frame = frames[la.id] else { return false }
                            return dropY >= frame.minY && dropY <= frame.maxY
                        }) {
                            PresentationMergeService.merge(
                                sourceID: id,
                                targetID: targetLA.id,
                                context: modelContext
                            )
                            return
                        }
                    }

                    // Otherwise reorder within the slot
                    var ids = currentLessons.map { $0.id }
                    if let existing = ids.firstIndex(of: id) { ids.remove(at: existing) }
                    let frames = currentFrames
                    let dict: [UUID: CGRect] = Dictionary(
                        currentLessons.compactMap { item -> (UUID, CGRect)? in
                            if let rect = frames[item.id] { return (item.id, rect) }
                            return nil
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: dict)
                    let bounded = max(0, min(insertionIndex, ids.count))
                    ids.insert(id, at: bounded)
                    let baseDate = AgendaSlot.baseDateForSlot(day: day, period: period, calendar: calendar)
                    let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: baseDate, calendar: calendar, spacingSeconds: 1)

                    for id in ids {
                        if let item = allLessonAssignments.first(where: { $0.id == id }) {
                            item.setScheduledFor(timeMap[id], using: AppCalendar.shared)
                        }
                    }
                    do {
                        try modelContext.save()
                    } catch {
                        Self.logger.warning("Failed to save context after reordering: \(error)")
                    }
                }
            }
        }
        return true
    }

    private func computeIndex(_ info: DropInfo) -> Int {
        let current = getCurrent()
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
}

struct PillFramePreference: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
