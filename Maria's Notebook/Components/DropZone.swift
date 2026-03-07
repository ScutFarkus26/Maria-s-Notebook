// swiftlint:disable file_length
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DropZone: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    let allLessonAssignments: [LessonAssignment]

    // Visual/drag state
    @State private var isTargeted: Bool = false
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var zoneSpaceID = UUID()
    @State private var insertionIndex: Int?

    // Inputs
    let day: Date
    let period: PlanningDayPeriod
    let onSelectLesson: (LessonAssignment) -> Void
    let onQuickActions: (LessonAssignment) -> Void
    let onPlanNext: (LessonAssignment) -> Void

    /// Synchronous helper that determines if a date is a non-school day using direct ModelContext fetches.
    private func isNonSchoolDaySync(_ date: Date) -> Bool {
        let day = AppCalendar.startOfDay(date)
        let cal = AppCalendar.shared

        // 1) Explicit non-school day wins
        do {
            var nsDescriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
            nsDescriptor.fetchLimit = 1
            let nonSchoolDays: [NonSchoolDay] = try modelContext.fetch(nsDescriptor)
            if !nonSchoolDays.isEmpty { return true }
        } catch {
            print("⚠️ [\(#function)] Failed to fetch non-school days: \(error)")
        }

        // 2) Weekends are non-school by default (Sunday=1, Saturday=7)
        let weekday = cal.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }

        // 3) Weekend override makes it a school day
        do {
            var ovDescriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.date == day })
            ovDescriptor.fetchLimit = 1
            let overrides: [SchoolDayOverride] = try modelContext.fetch(ovDescriptor)
            if !overrides.isEmpty { return false }
        } catch {
            print("⚠️ [\(#function)] Failed to fetch school day overrides: \(error)")
        }
        return true
    }

    private var isNonSchool: Bool { isNonSchoolDaySync(day) }

    private var scheduledLessonsForSlot: [LessonAssignment] {
        allLessonAssignments.filter { la in
            guard let scheduled = la.scheduledFor, !la.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day) && isInSlot(scheduled, period: period)
        }
        .sorted { ($0.scheduledFor ?? .distantPast) < ($1.scheduledFor ?? .distantPast) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Minimal card background matching the rest of the app
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isTargeted ? 0.04 : 0.02))

            // Accent outline when targeted
            if isTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 3)
                    .allowsHitTesting(false)
            }

            // Non-school overlay
            if isNonSchool {
                Text("No School")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                if scheduledLessonsForSlot.isEmpty {
                    Text("No plans yet")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                } else {
                    ForEach(Array(scheduledLessonsForSlot.enumerated()), id: \.element.id) { _, la in
                        lessonPillView(for: la)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 22, leading: 12, bottom: 12, trailing: 12))
            .overlay(
                // Insertion indicator line, similar to Agenda view
                GeometryReader { proxy in
                    if let idx = insertionIndex {
                        let frames: [(UUID, CGRect)] = scheduledLessonsForSlot.compactMap { item in
                            if let rect = itemFrames[item.id] { return (item.id, rect) }
                            return nil
                        }.sorted { $0.1.minY < $1.1.minY }

                        if frames.isEmpty {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width - 24, height: 3)
                                .position(x: proxy.size.width / 2, y: 12)
                        } else {
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
            Task { @MainActor in
                itemFrames = frames
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDrop(of: [UTType.text], delegate: BoardDropDelegate(
            calendar: calendar,
            modelContext: modelContext,
            allLessonAssignments: allLessonAssignments,
            day: day,
            period: period,
            getCurrent: { scheduledLessonsForSlot },
            itemFramesProvider: { itemFrames },
            onTargetChange: { targeted in
                adaptiveWithAnimation(.easeInOut(duration: 0.15)) { isTargeted = targeted }
            },
            onInsertionIndexChange: { idx in
                if insertionIndex != idx {
                    adaptiveWithAnimation(
                        .interactiveSpring(response: 0.16, dampingFraction: 0.85)
                    ) { insertionIndex = idx }
                }
            }
        ))
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(isNonSchool)
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
            PresentationPill(
                snapshot: la.snapshot(),
                day: day,
                sourceLessonAssignmentID: la.id,
                targetLessonAssignmentID: la.id
            )
            .opacity(0.85)
        }
        .onTapGesture { onSelectLesson(la) }
        .contextMenu {
            Button { onQuickActions(la) } label: { Label("Quick Actions…", systemImage: "bolt") }
            Button { onPlanNext(la) } label: {
                Label("Plan Next Lesson in Group", systemImage: SFSymbol.Time.calendarBadgePlus)
            }
            Button { onSelectLesson(la) } label: { Label("Open Details", systemImage: SFSymbol.Status.infoCircle) }
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

    private func isInSlot(_ date: Date, period: PlanningDayPeriod) -> Bool {
        let hour = calendar.component(.hour, from: date)
        switch period {
        case .morning: return hour < 12
        case .afternoon: return hour >= 12
        }
    }

    private func dateForSlot(day: Date, period: PlanningDayPeriod) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        let hour: Int
        switch period {
        case .morning: hour = UIConstants.morningHour
        case .afternoon: hour = UIConstants.afternoonHour
        }
        return calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
    }

    private struct PillFramePreference: PreferenceKey {
        nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }
}

// MARK: - BoardDropDelegate (Board view drop handling with live insertion feedback)

struct BoardDropDelegate: DropDelegate {
    let calendar: Calendar
    let modelContext: ModelContext
    let allLessonAssignments: [LessonAssignment]
    let day: Date
    let period: PlanningDayPeriod
    let getCurrent: () -> [LessonAssignment]
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

    func performDropFromProvidersAsync(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first, provider.canLoadObject(ofClass: NSString.self) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let ns = reading as? NSString else { return }
            let payload = ns as String
            Task { @MainActor in
                self.handleDropPayload(payload: payload, location: location)
            }
        }
        return true
    }

    @MainActor
    private func handleDropPayload(payload: String, location: CGPoint) {
        if payload.hasPrefix("STUDENT_TO_INBOX:") || payload.hasPrefix("STUDENT_TO_SLOT:") {
            handleStudentToSlotPayload(payload: payload, location: location)
            return
        }
        handlePlainIDPayload(payload: payload, location: location)
    }

    @MainActor
    private func handleStudentToSlotPayload(payload: String, location: CGPoint) {
        let parts = payload.split(separator: ":")
        guard parts.count == 4,
              let srcID = UUID(uuidString: String(parts[1])),
              let lessonID = UUID(uuidString: String(parts[2])),
              let studentID = UUID(uuidString: String(parts[3])) else {
            return
        }

        let current = getCurrent()
        var ids = current.map { $0.id }
        let frames = itemFramesProvider()
        let dict = buildFramesDictionary(current: current, frames: frames)
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: dict)

        let targetLA = findOrCreateTargetLessonAssignment(lessonID: lessonID, studentID: studentID)

        ids.removeAll(where: { $0 == targetLA.id })
        let boundedIndex = max(0, min(insertionIndex, ids.count))
        ids.insert(targetLA.id, at: boundedIndex)
        let baseDate = dateForSlot(day: day, period: period)
        let timeMap = PlanningDropUtils.assignSequentialTimes(
            ids: ids, base: baseDate, calendar: calendar,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )
        applyTimeMap(ids: ids, timeMap: timeMap, targetLA: targetLA)

        removeStudentFromSource(srcID: srcID, studentID: studentID)
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to save model context: \(error)")
        }
    }

    @MainActor
    private func handlePlainIDPayload(payload: String, location: CGPoint) {
        guard let id = UUID(uuidString: payload.trimmed()) else {
            return
        }

        let current = getCurrent()

        // Check if the drop landed on a pill for the same lesson — merge instead of reorder
        if let source = allLessonAssignments.first(where: { $0.id == id }), !source.isGiven {
            let frames = itemFramesProvider()
            let dropY = location.y
            if let targetLA = current.first(where: { la in
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

        var ids = current.map { $0.id }
        if let existing = ids.firstIndex(of: id) {
            ids.remove(at: existing)
        }

        let frames = itemFramesProvider()
        let dict = buildFramesDictionary(current: current, frames: frames)
        let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: dict)
        let bounded = max(0, min(insertionIndex, ids.count))
        ids.insert(id, at: bounded)

        let baseDate = dateForSlot(day: day, period: period)
        let timeMap = PlanningDropUtils.assignSequentialTimes(
            ids: ids, base: baseDate, calendar: calendar,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )
        applyTimeMapForReorder(ids: ids, timeMap: timeMap)
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [\(#function)] Failed to save model context: \(error)")
        }
    }

    private func buildFramesDictionary(current: [LessonAssignment], frames: [UUID: CGRect]) -> [UUID: CGRect] {
        Dictionary(
            current.compactMap { item -> (UUID, CGRect)? in
                guard let rect = frames[item.id] else { return nil }
                return (item.id, rect)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    @MainActor
    private func findOrCreateTargetLessonAssignment(lessonID: UUID, studentID: UUID) -> LessonAssignment {
        let studentIDString = studentID.uuidString
        let lessonIDString = lessonID.uuidString

        if let existing = allLessonAssignments.first(where: { la in
            la.lessonID == lessonIDString && la.scheduledFor == nil && !la.isGiven && la.studentIDs == [studentIDString]
        }) {
            return existing
        }

        let new = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [studentID])

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
        return new
    }

    @MainActor
    private func applyTimeMap(ids: [UUID], timeMap: [UUID: Date], targetLA: LessonAssignment) {
        for id in ids {
            if let item = allLessonAssignments.first(where: { $0.id == id }) {
                item.setScheduledFor(timeMap[id], using: AppCalendar.shared)
                if let lesson = item.lesson {
                    GroupTrackService.autoEnrollInTrackIfNeeded(
                        lesson: lesson,
                        studentIDs: item.studentIDs,
                        modelContext: modelContext
                    )
                }
            }
            if id == targetLA.id {
                targetLA.setScheduledFor(timeMap[id], using: AppCalendar.shared)
                if let lesson = targetLA.lesson {
                    GroupTrackService.autoEnrollInTrackIfNeeded(
                        lesson: lesson,
                        studentIDs: targetLA.studentIDs,
                        modelContext: modelContext
                    )
                }
            }
        }
    }

    @MainActor
    private func applyTimeMapForReorder(ids: [UUID], timeMap: [UUID: Date]) {
        for id in ids {
            if let item = allLessonAssignments.first(where: { $0.id == id }) {
                item.setScheduledFor(timeMap[id], using: AppCalendar.shared)
                if let lesson = item.lesson {
                    GroupTrackService.autoEnrollInTrackIfNeeded(
                        lesson: lesson,
                        studentIDs: item.studentIDs,
                        modelContext: modelContext
                    )
                }
            }
        }
    }

    @MainActor
    private func removeStudentFromSource(srcID: UUID, studentID: UUID) {
        guard let src = allLessonAssignments.first(where: { $0.id == srcID }) else {
            return
        }

        let studentIDString = studentID.uuidString
        src.studentIDs.removeAll { $0 == studentIDString }
        src.students.removeAll { $0.id == studentID }

        if src.studentIDs.isEmpty {
            modelContext.delete(src)
        }
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

    private func dateForSlot(day: Date, period: PlanningDayPeriod) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        let hour: Int = (period == .morning) ? UIConstants.morningHour : UIConstants.afternoonHour
        return calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
    }
}
