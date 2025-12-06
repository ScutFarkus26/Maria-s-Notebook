import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DropZone: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    let allStudentLessons: [StudentLesson]
    @State private var isTargeted: Bool = false
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var zoneSpaceID = UUID()

    let day: Date
    let period: PlanningDayPeriod
    let onSelectLesson: (StudentLesson) -> Void
    let onQuickActions: (StudentLesson) -> Void
    let onPlanNext: (StudentLesson) -> Void

    private var isNonSchool: Bool { SchoolCalendar.isNonSchoolDay(day, using: modelContext) }

    private var scheduledLessonsForSlot: [StudentLesson] {
        allStudentLessons.filter { sl in
            guard let scheduled = sl.scheduledFor, !sl.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day) && isInSlot(scheduled, period: period)
        }
        .sorted { lhs, rhs in
            (lhs.scheduledFor ?? .distantPast) < (rhs.scheduledFor ?? .distantPast)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: UIConstants.dropZoneCornerRadius, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: UIConstants.dropZoneStrokeDash))
                .foregroundStyle(Color.primary.opacity(0.25))

            RoundedRectangle(cornerRadius: UIConstants.dropZoneCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .allowsHitTesting(false)

            if isTargeted {
                RoundedRectangle(cornerRadius: UIConstants.dropZoneCornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 3)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            
            if isNonSchool {
                Text("No School")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                if scheduledLessonsForSlot.isEmpty {
                    Text("Drop lesson here")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scheduledLessonsForSlot, id: \.id) { sl in
                        StudentLessonPill(snapshot: sl.snapshot(), day: Date(), sourceStudentLessonID: sl.id, targetStudentLessonID: sl.id)
                            .onTapGesture { onSelectLesson(sl) }
                            .contextMenu {
                                Button { onQuickActions(sl) } label: { Label("Quick Actions…", systemImage: "bolt") }
                                Button { onPlanNext(sl) } label: { Label("Plan Next Lesson in Group", systemImage: "calendar.badge.plus") }
                                Button { onSelectLesson(sl) } label: { Label("Open Details", systemImage: "info.circle") }
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
                }
            }
            .padding(UIConstants.dropZoneInnerPadding)
        }
        .coordinateSpace(name: zoneSpaceID)
        .onPreferenceChange(PillFramePreference.self) { frames in
            itemFrames = frames
        }
        .contentShape(Rectangle())
        .disabled(isNonSchool)
        .dropDestination(for: String.self, action: { items, location in
            if isNonSchool { return false }

            if let first = items.first, let payload = DragPayload.decode(first) {
                let srcID = payload.sourceID
                let lessonID = payload.lessonID
                let studentID = payload.studentID
                let current = scheduledLessonsForSlot
                var ids = current.map { $0.id }
                let framesDict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
                    if let rect = itemFrames[item.id] { return (item.id, rect) }
                    return nil
                })
                let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: framesDict)
                let existing = allStudentLessons.first(where: { $0.lessonID == lessonID && $0.scheduledFor == nil && !$0.isGiven && $0.studentIDs == [studentID] })
                let targetSL: StudentLesson
                if let ex = existing {
                    targetSL = ex
                } else {
                    let new = StudentLesson(
                        id: UUID(),
                        lessonID: lessonID,
                        studentIDs: [studentID],
                        createdAt: Date(),
                        scheduledFor: nil,
                        givenAt: nil,
                        notes: "",
                        needsPractice: false,
                        needsAnotherPresentation: false,
                        followUpWork: ""
                    )
                    let lessonFetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
                    let studentFetch = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
                    new.lesson = (try? modelContext.fetch(lessonFetch))?.first
                    if let s = (try? modelContext.fetch(studentFetch))?.first { new.students = [s] }
                    new.syncSnapshotsFromRelationships()
                    modelContext.insert(new)
                    targetSL = new
                }
                ids.removeAll(where: { $0 == targetSL.id })
                let boundedIndex = max(0, min(insertionIndex, ids.count))
                ids.insert(targetSL.id, at: boundedIndex)
                let base = dateForSlot(day: day, period: period)
                let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: base, calendar: calendar, spacingSeconds: UIConstants.scheduleSpacingSeconds)
                for id in ids {
                    if let item = allStudentLessons.first(where: { $0.id == id }) { item.scheduledFor = timeMap[id] }
                    if id == targetSL.id { targetSL.scheduledFor = timeMap[id] }
                }
                if let src = allStudentLessons.first(where: { $0.id == srcID }) {
                    src.studentIDs.removeAll { $0 == studentID }
                    if src.studentIDs.isEmpty {
                        modelContext.delete(src)
                    } else {
                        let remainingIDs = src.studentIDs
                        let fetch = FetchDescriptor<Student>(predicate: #Predicate { remainingIDs.contains($0.id) })
                        let fetched = (try? modelContext.fetch(fetch)) ?? []
                        src.students = fetched
                        src.syncSnapshotsFromRelationships()
                    }
                }
                Task { @MainActor in 
                    try? modelContext.save()
                }
                return true
            }

            guard let idString = items.first, let id = UUID(uuidString: idString) else { return false }
            guard let sl = allStudentLessons.first(where: { $0.id == id }) else { return false }
            let current = scheduledLessonsForSlot
            var ids = current.map { $0.id }
            let sortedFrames: [(UUID, CGRect)] = current.compactMap { item in
                if let rect = itemFrames[item.id] { return (item.id, rect) }
                return nil
            }
            let framesDict = Dictionary(uniqueKeysWithValues: sortedFrames.map { ($0.0, $0.1) })
            let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: framesDict)
            if let existingIndex = ids.firstIndex(of: sl.id) { ids.remove(at: existingIndex) }
            let boundedIndex = max(0, min(insertionIndex, ids.count))
            ids.insert(sl.id, at: boundedIndex)
            let base = dateForSlot(day: day, period: period)
            let timeMap = PlanningDropUtils.assignSequentialTimes(ids: ids, base: base, calendar: calendar, spacingSeconds: UIConstants.scheduleSpacingSeconds)
            for id in ids { if let item = allStudentLessons.first(where: { $0.id == id }) { item.scheduledFor = timeMap[id] } }
            Task { @MainActor in 
                try? modelContext.save()
            }
            return true
        }, isTargeted: { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isTargeted = hovering
            }
        })
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
        static var defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }
}
