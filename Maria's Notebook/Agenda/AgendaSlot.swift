import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AgendaSlot: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    let allStudentLessons: [StudentLesson]
    let day: Date
    let period: DayPeriod
    let onSelectLesson: (StudentLesson) -> Void
    let onQuickActions: (StudentLesson) -> Void
    let onPlanNext: (StudentLesson) -> Void
    let onMoveToInbox: (StudentLesson) -> Void
    let onMoveStudents: (StudentLesson) -> Void

    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var zoneSpaceID = UUID()
    @State private var isTargeted: Bool = false
    @State private var insertionIndex: Int? = nil

    private var scheduledLessonsForSlot: [StudentLesson] {
        allStudentLessons.filter { sl in
            guard let scheduled = sl.scheduledFor, !sl.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day) && isInSlot(scheduled, period: period)
        }
        .sorted { ($0.scheduledFor ?? .distantPast) < ($1.scheduledFor ?? .distantPast) }
    }

    init(
        allStudentLessons: [StudentLesson],
        day: Date,
        period: DayPeriod,
        onSelectLesson: @escaping (StudentLesson) -> Void,
        onQuickActions: @escaping (StudentLesson) -> Void,
        onPlanNext: @escaping (StudentLesson) -> Void,
        onMoveToInbox: @escaping (StudentLesson) -> Void,
        onMoveStudents: @escaping (StudentLesson) -> Void
    ) {
        self.allStudentLessons = allStudentLessons
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
                    ForEach(Array(scheduledLessonsForSlot.enumerated()), id: \.element.id) { index, sl in
                        lessonPillView(for: sl)
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
            allStudentLessons: allStudentLessons,
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
    private func lessonPillView(for sl: StudentLesson) -> some View {
        StudentLessonPill(
            snapshot: sl.snapshot(),
            day: day,
            sourceStudentLessonID: sl.id,
            targetStudentLessonID: sl.id
        )
        .draggable(sl.id.uuidString) {
            // Custom drag preview
            StudentLessonPill(
                snapshot: sl.snapshot(),
                day: day,
                sourceStudentLessonID: sl.id,
                targetStudentLessonID: sl.id
            )
            .opacity(0.8)
        }
        .onTapGesture {
            onSelectLesson(sl)
        }
        .contextMenu {
            Button {
                onQuickActions(sl)
            } label: {
                Label("Quick Actions…", systemImage: "bolt")
            }
            
            Button {
                onPlanNext(sl)
            } label: {
                Label("Plan Next Lesson in Group", systemImage: "calendar.badge.plus")
            }
            
            Button {
                onSelectLesson(sl)
            } label: {
                Label("Open Details", systemImage: "info.circle")
            }
            
            Button {
                onMoveStudents(sl)
            } label: {
                Label("Move Students…", systemImage: "person.2.arrow.right")
            }
            
            Button {
                onMoveToInbox(sl)
            } label: {
                Label("Move to Inbox", systemImage: "tray")
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
    let calendar: Calendar
    let modelContext: ModelContext
    let allStudentLessons: [StudentLesson]
    let day: Date
    let period: DayPeriod
    let getCurrent: () -> [StudentLesson]
    let itemFramesProvider: () -> [UUID: CGRect]
    let onTargetChange: (Bool) -> Void
    let onInsertionIndexChange: (Int?) -> Void

    init(
        calendar: Calendar,
        modelContext: ModelContext,
        allStudentLessons: [StudentLesson],
        day: Date,
        period: DayPeriod,
        getCurrent: @escaping () -> [StudentLesson],
        itemFramesProvider: @escaping () -> [UUID: CGRect],
        onTargetChange: @escaping (Bool) -> Void,
        onInsertionIndexChange: @escaping (Int?) -> Void
    ) {
        self.calendar = calendar
        self.modelContext = modelContext
        self.allStudentLessons = allStudentLessons
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
                    let allStudentLessons = self.allStudentLessons
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
                        if let item = allStudentLessons.first(where: { $0.id == id }) {
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
                let allStudentLessons = self.allStudentLessons
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

                        let existing = allStudentLessons.first(where: { sl in
                            let matchesLesson = sl.resolvedLessonID == lessonID
                            let isUnscheduled = sl.scheduledFor == nil
                            let isNotGiven = !sl.isGiven
                            let matchesStudentSet = Set(sl.resolvedStudentIDs) == Set([studentID])
                            return matchesLesson && isUnscheduled && isNotGiven && matchesStudentSet
                        })
                        let targetSL: StudentLesson
                        if let ex = existing {
                            targetSL = ex
                        } else {
                            let new = StudentLessonFactory.makeUnscheduled(lessonID: lessonID, studentIDs: [studentID])
                            var lessonFetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
                            lessonFetch.fetchLimit = 1
                            var studentFetch = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
                            studentFetch.fetchLimit = 1
                            do {
                                new.lesson = try modelContext.fetch(lessonFetch).first
                            } catch {
                                print("⚠️ [\(#function)] Failed to fetch lesson: \(error)")
                            }
                            do {
                                if let s = try modelContext.fetch(studentFetch).first {
                                    new.students = [s]
                                }
                            } catch {
                                print("⚠️ [\(#function)] Failed to fetch student: \(error)")
                            }
                            modelContext.insert(new)
                            targetSL = new
                        }

                        ids.removeAll(where: { $0 == targetSL.id })
                        let boundedIndex = max(0, min(insertionIndex, ids.count))
                        ids.insert(targetSL.id, at: boundedIndex)
                        let baseDate = AgendaSlot.baseDateForSlot(day: day, period: period, calendar: calendar)
                        let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: baseDate, calendar: calendar, spacingSeconds: 1)
                        
                        for id in ids {
                            if let item = allStudentLessons.first(where: { $0.id == id }) { item.setScheduledFor(timeMap[id], using: AppCalendar.shared) }
                            if id == targetSL.id { targetSL.setScheduledFor(timeMap[id], using: AppCalendar.shared) }
                        }
                        
                        if let src = allStudentLessons.first(where: { $0.id == srcID }) {
                            src.studentIDs.removeAll { $0 == studentID.uuidString }
                            src.students.removeAll { $0.id == studentID }
                            if src.studentIDs.isEmpty { modelContext.delete(src) } else { /* Removed src.syncSnapshotsFromRelationships() */ }
                        }
                        do {
                            try modelContext.save()
                        } catch {
                            print("⚠️ [\(#function)] Failed to save context after student move: \(error)")
                        }
                        
                        // Auto-enroll students in track if lesson belongs to a track
                        if let lesson = targetSL.lesson {
                            GroupTrackService.autoEnrollInTrackIfNeeded(
                                lesson: lesson,
                                studentIDs: targetSL.studentIDs,
                                modelContext: modelContext
                            )
                        }
                        return
                    }
                }

                // Fallback: treat as a plain StudentLesson ID and reorder within the slot
                if let id = UUID(uuidString: payload.trimmed()) {
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
                        if let item = allStudentLessons.first(where: { $0.id == id }) {
                            item.setScheduledFor(timeMap[id], using: AppCalendar.shared)
                        }
                    }
                    do {
                        try modelContext.save()
                    } catch {
                        print("⚠️ [\(#function)] Failed to save context after reordering: \(error)")
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
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
